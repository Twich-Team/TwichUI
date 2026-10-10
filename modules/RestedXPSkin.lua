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
-- Not covered (RestedXP draws them itself or another addon owns them): the v2 guide window (beta; only
-- the theme's colours and font reach it), the map arrow and pins, RestedXP's right-click menus
-- (Blizzard's dropdown), tooltips, its options, the tracker, talent and importer windows.
--
-- Saved: TwichUIDB.modules.restedxpSkin (the switch, off by default), TwichUIDB.ui.restedxpSkin (the
-- background and border look; MenuStyle's), TwichUIDB.ui.restedxpSkinText (fonts, outlines, colours) and
-- TwichUIDB.ui.restedxpSkinState (the name of the theme to go back to). Frames and fonts are never saved.

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
}
local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
Skin.OUTLINE_CHOICES = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" } }
Skin.THEME, Skin.SWITCH = THEME, SWITCH

local Look = R.MenuStyle.New("restedxpSkin", LOOK_DEFAULTS)
Skin.Look = Look

---------------------------------------------------------------------------
-- Runtime state. Nothing here is saved.
---------------------------------------------------------------------------
local enabled = false           -- the switch is on and Start has run
local RXP                       -- RestedXP's addon object, once found and usable
local theme                     -- the one theme table registered with RestedXP (changed in place)
local hooks = { render = false, stepText = false, fontSize = false }
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

local FinishAll

---------------------------------------------------------------------------
-- Settings: the look is MenuStyle's; the text settings are here.
---------------------------------------------------------------------------
local function ValidText(key, value)
    if key == "titleFont" or key == "bodyFont" then return R.Borders.ValidName(value)
    elseif key == "titleOutline" or key == "bodyOutline" then return type(value) == "string" and OUTLINES[value] ~= nil
    elseif key == "titleColor" or key == "bodyColor" then
        return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif key == "tintScrollbar" then return type(value) == "boolean" end
    return false
end

local function SavedText()
    local ui = TwichUIDB and TwichUIDB.ui
    local saved = ui and ui.restedxpSkinText
    return type(saved) == "table" and saved or nil
end

local Text = { DEFAULTS = TEXT_DEFAULTS }
Skin.Text = Text

function Text.Get(key)
    local saved = SavedText()
    local value = saved and saved[key]
    if ValidText(key, value) then return value end
    return TEXT_DEFAULTS[key]
end

local function Changed()
    rev = rev + 1
    if enabled and Skin.Request then Skin.Request(false) end
end

function Text.Set(key, value)
    if TEXT_DEFAULTS[key] == nil or not ValidText(key, value) then return false end
    TwichUIDB.ui = TwichUIDB.ui or {}
    if type(TwichUIDB.ui.restedxpSkinText) ~= "table" then TwichUIDB.ui.restedxpSkinText = {} end
    TwichUIDB.ui.restedxpSkinText[key] = value
    Changed()
    return true
end

function Text.Reset()
    if TwichUIDB and TwichUIDB.ui then TwichUIDB.ui.restedxpSkinText = nil end
    Changed()
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
        if fallbacks.title or fallbacks.body then Changed() end
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
    changed = Set(theme.bottomFrameHighlight, er, eg, eb, 0.5) or changed
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

local want = {}   -- the targets: title/body path and flags, title/body/accent colours
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

local canonPath, canonFlags = {}, {}   -- a font as the game reports it back, by the one asked for

-- Sets a string's face and outline (never its size, which is RestedXP's Guide Font Size). True if it changed.
local function StyleFont(fs, path, flags)
    local current, size, currentFlags = fs:GetFont()
    if not (current and size) then return false end
    currentFlags = currentFlags or ""
    if (current == path or current == canonPath[path]) and (currentFlags == flags or currentFlags == canonFlags[flags]) then
        return false
    end
    if fs:SetFont(path, size, flags) == false then return false end
    local now, _, nowFlags = fs:GetFont()
    if now and now ~= path then canonPath[path] = now end
    if nowFlags and nowFlags ~= flags then canonFlags[flags] = nowFlags end
    return true
end

local relayout = false   -- a face changed: RestedXP's own text layout runs once more

local function StyleText(fs, title)
    if not (fs and fs.GetFont and fs.GetTextColor) then return end
    if StyleFont(fs, title and want.titlePath or want.bodyPath, title and want.titleFlags or want.bodyFlags) then
        relayout = true
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

-- RestedXP's own backdrops: the tables its frames are given. Only a frame showing one of them is
-- drawn on (a frame RestedXP shows without a backdrop, such as the item frame with its background
-- hidden in its options, stays as it is).
local function RestedXPBackdrops()
    local frame = _G.RXPFrame
    local b = frame and frame.backdrop
    if type(b) == "table" then return b.edge, b.guideName end
end

local function StyleBackdrop(frame, edgeInfo, guideInfo)
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
    local origin = current
    if rec and current == rec.info then origin = rec.origin end
    Look.Apply(frame)
    if not rec then
        rec = {}
        owned[frame] = rec
    end
    rec.info, rec.origin, rec.rev = frame.backdropInfo, origin, rev
    touched = true
end

-- The window's header and footer art is a gradient banner; under this look the frame's own background
-- shows instead.
local function StyleBanner(holder)
    local bg = holder and holder.bg
    if bg and bg.GetAlpha and bg:GetAlpha() ~= 0 then bg:SetAlpha(0) touched = true end
end

local SCROLL_PIECES = { "Normal", "Highlight", "Pushed", "Disabled" }
local SCROLL_BUTTONS = { "ScrollUpButton", "ScrollDownButton" }

local function Tint(texture, r, g, b)
    if not (texture and texture.GetVertexColor) then return end
    local cr, cg, cb = texture:GetVertexColor()
    if not (cr and Near(cr, cg, cb, r, g, b)) then texture:SetVertexColor(r, g, b) end
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

local function FinishWindow(edgeInfo, guideInfo)
    local frame = _G.RXPFrame
    if not frame then return end
    StyleBackdrop(frame.BottomFrame, edgeInfo, guideInfo)
    StyleBackdrop(frame.GuideName, edgeInfo, guideInfo)
    StyleBackdrop(frame.Footer, edgeInfo, guideInfo)
    StyleBanner(frame.GuideName)
    StyleBanner(frame.Footer)
    StyleText(frame.GuideName and frame.GuideName.text, true)
    StyleText(frame.Footer and frame.Footer.text, true)
    if want.tint then TintScrollbar(want.ar, want.ag, want.ab) end
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
                StyleBackdrop(number, edgeInfo, guideInfo)
                StyleText(number.text, true)
            end
            local elements = step.elements
            if type(elements) == "table" then
                for j = 1, #elements do StyleText(elements[j].text, false) end
            end
        end
    end
    local rows = frame and frame.ScrollChild and frame.ScrollChild.framePool
    if type(rows) == "table" then
        for i = 1, #rows do
            local row = rows[i]
            StyleText(row.text, false)
            if row.number then StyleText(row.number.text, false) end
        end
    end
end

local function FinishTray(tray, edgeInfo, guideInfo)
    if not tray then return end
    StyleBackdrop(tray, edgeInfo, guideInfo)
    local title = tray.title
    if title then
        StyleBackdrop(title, edgeInfo, guideInfo)
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

-- One pass over everything this skin touches. The frames are RestedXP's own: its window, its step
-- cards and rows (a pool it grows only as steps need), and its two small trays.
function FinishAll()
    if InCombatLockdown() then waitingCombat = true; stats.skipped = stats.skipped + 1; return end
    stats.passes = stats.passes + 1
    local edgeInfo, guideInfo = RestedXPBackdrops()
    Wants()
    relayout = false
    FinishWindow(edgeInfo, guideInfo)
    FinishSteps(edgeInfo, guideInfo)
    FinishTrays(edgeInfo, guideInfo)
    -- A different face changes how tall the lines are. RestedXP's own layout settles that; once.
    if relayout and not busy then
        local csf = _G.RXPFrame and _G.RXPFrame.CurrentStepFrame
        if csf and type(csf.UpdateText) == "function" then
            busy = true
            pcall(csf.UpdateText)
            busy = false
        end
    end
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
    if rec.info ~= nil and frame.backdropInfo == rec.info and rec.origin and frame.SetBackdrop then
        frame:ClearBackdrop()
        frame:SetBackdrop(rec.origin)
        if background then frame:SetBackdropColor(background[1], background[2], background[3], background[4]) end
    end
end

local function UnstyleText(fs, title)
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
        UnstyleText(frame.GuideName and frame.GuideName.text, true)
        UnstyleText(frame.Footer and frame.Footer.text, true)
        local pool = frame.CurrentStepFrame and frame.CurrentStepFrame.framePool
        for i = 1, type(pool) == "table" and #pool or 0 do
            local step = pool[i]
            if step.number then UnstyleText(step.number.text, true) end
            for j = 1, type(step.elements) == "table" and #step.elements or 0 do UnstyleText(step.elements[j].text, false) end
        end
        local rows = frame.ScrollChild and frame.ScrollChild.framePool
        for i = 1, type(rows) == "table" and #rows or 0 do
            UnstyleText(rows[i].text, false)
            if rows[i].number then UnstyleText(rows[i].number.text, false) end
        end
        TintScrollbar(1, 1, 1)
    end
    if RXP then
        UnstyleTray(RXP.activeItemFrame)
        UnstyleTray(RXP.targeting and RXP.targeting.activeTargetFrame)
    end
    for key in pairs(owned) do owned[key] = nil end
    touched = false
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

local function OnStepText()
    if not busy and Active() then
        FinishAll()
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
    if not hooks.fontSize and type(RXP.UpdateGuideFontSize) == "function" then
        hooks.fontSize = true
        hooksecurefunc(RXP, "UpdateGuideFontSize", OnFontSize)
    end
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
