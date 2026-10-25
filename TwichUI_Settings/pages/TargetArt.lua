-- TwichUI settings: Target dragon artwork (targetart/). The switch and whether EllesmereUI's target frame was found,
-- the artwork for each kind of enemy, how it is placed and drawn, and a preview: a sample frame of this window's own
-- (always there, clearly not your target) and, on request, the chosen artwork on your real target frame. Every value
-- is checked and saved by the core's targetart/Config.lua; this file only describes rows that call its Get/Set. Nothing
-- here is needed for the artwork to work.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.TargetArtPage = P

local W = 644                  -- the settings window's content width
local HOST_H = 300
local CANVAS_W, CANVAS_H = 430, 200
local CHOICE_STEP = 25        -- the artwork buttons beside the sample, one under another
local SAMPLE_W, SAMPLE_H = 181, 52   -- EllesmereUI's default target frame, when the real one can't be measured

local function Wg() return R.SettingsWidgets end
local function TA() return R.TargetArt end
local function D() return R.TargetArtDisplay end
local function On() return R:Enabled("targetArt") end

---------------------------------------------------------------------------
-- The sample frame
---------------------------------------------------------------------------
local f, built
local placement = {}

-- The real frame's size when it is attached and readable, so the sample matches it; else EllesmereUI's default.
local function SampleSize()
    local s = D().Snapshot()
    local host = s.host
    if host then
        local w, h = host:GetWidth(), host:GetHeight()
        if type(w) == "number" and type(h) == "number" and w >= 1 and h >= 1 then
            return math.min(w, CANVAS_W - 80), h, true
        end
    end
    return SAMPLE_W, SAMPLE_H, false
end

local function Refresh()
    if not (f and built and f:IsVisible()) then return end
    local ta, d = TA(), D()
    local w, h, real = SampleSize()
    f.sample:SetSize(w, h)
    f.health:SetHeight(math.max(1, h * 0.85))
    f.size:SetText(real and ("Drawn at your target frame's size, %d x %d."):format(math.floor(w + 0.5), math.floor(h + 0.5))
        or ("Drawn at EllesmereUI's default target frame size, %d x %d (your frame isn't available to measure)."):format(w, h))
    local id = d.PreviewArt()
    local p = ta.Placement(id, h, nil, placement)
    local tex = f.art
    tex:SetTexture(ta.ART[id].path)
    tex:SetTexCoord(p.l, p.r, p.t, p.b)
    tex:SetSize(p.w, p.h)
    tex:ClearAllPoints()
    tex:SetPoint(p.point, f.sample, p.relPoint, p.x, p.y)
    tex:SetAlpha(ta.Get("opacity") / 100)
    tex:SetDrawLayer(ta.Get("layer") == "behind" and "BACKGROUND" or "OVERLAY", 1)
    for _, b in ipairs(f.choices) do b.mark:SetShown(b.id == id) end
    f.live:SetText(d.PreviewActive() and "Stop" or "Show on my target frame")
    f.liveNote:SetText(d.PreviewActive()
        and "Showing on your target frame whatever you target. Target something to see it; it stops when you close these settings or enter combat."
        or "Puts the artwork chosen here on your real target frame, whatever the target's kind, until you stop it.")
end

local function Build()
    built = true
    local G, ta = Wg(), TA()
    local pal = G.pal
    f.about = G.Text(f, "small")
    f.about:SetPoint("TOPLEFT", 4, -2)
    f.about:SetWidth(W - 8)
    f.about:SetText("A sample frame, not your target: it shows how the artwork sits with the settings above. Choose which artwork it uses on the right; that choice is only for the preview and saves nothing.")

    local canvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
    canvas:SetSize(CANVAS_W, CANVAS_H)
    canvas:SetPoint("TOPLEFT", 4, -32)
    G.Surface(canvas, pal.well, 0.95, pal.bronzeLo, 0.5)
    canvas:SetClipsChildren(true)   -- a large scale or offset stays inside the preview
    f.canvas = canvas

    local sample = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    sample:SetPoint("TOPLEFT", 40, -78)
    G.Surface(sample, pal.surface, 1, pal.bronzeLo, 0.8)
    f.sample = sample
    local health = sample:CreateTexture(nil, "BORDER")
    health:SetColorTexture(0.42, 0.16, 0.13, 0.9)
    health:SetPoint("TOPLEFT", 1, -1)
    health:SetPoint("TOPRIGHT", -1, -1)
    f.health = health
    local name = G.Text(sample, "body")
    name:SetPoint("LEFT", 8, 4)
    name:SetText("Sample enemy")
    f.art = sample:CreateTexture(nil, "OVERLAY", nil, 1)

    f.size = G.Text(f, "meta")
    f.size:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -4)
    f.size:SetWidth(CANVAS_W)

    local x = CANVAS_W + 20
    local label = G.Text(f, "heading")
    label:SetPoint("TOPLEFT", x, -34)
    label:SetText("Artwork in this preview")
    f.choices = {}
    for i, id in ipairs(ta.ART_ORDER) do
        local b = G.Button(f, ta.ART[id].label, 170, "secondary", function()
            D().SetPreviewArt(id)
            Refresh()
            K.RefreshOverview()   -- the fine-tune rows follow this choice
        end)
        b:SetPoint("TOPLEFT", x, -34 - i * CHOICE_STEP)
        b.id = id
        b.mark = b:CreateTexture(nil, "OVERLAY")
        b.mark:SetColorTexture(pal.teal[1], pal.teal[2], pal.teal[3], 1)
        b.mark:SetSize(3, 14)
        b.mark:SetPoint("LEFT", 4, 0)
        f.choices[i] = b
    end
    f.live = G.Button(f, "Show on my target frame", 170, "secondary", function()
        local d = D()
        if d.PreviewActive() then d.PreviewStop()
        else
            local ok, why = d.PreviewStart()
            if not ok then
                R.Print(why == "combat" and "the preview waits until you are out of combat." or "turn the target dragon artwork on first.")
            end
        end
        Refresh()
        K.RefreshOverview()
    end)
    f.live:SetPoint("TOPLEFT", x, -34 - (#ta.ART_ORDER + 1) * CHOICE_STEP - 6)
    f.liveNote = G.Text(f, "meta")
    f.liveNote:SetPoint("TOPLEFT", f.live, "BOTTOMLEFT", 0, -4)
    f.liveNote:SetWidth(W - x - 8)
end

-- The page's frame (the window shows it under "Preview"). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build() end
        Refresh()
    end)
    f:SetScript("OnHide", function() if D() then D().PreviewStop() end end)   -- leaving the page or closing the window
    return f
end

if R.TargetArt then R.TargetArt.Subscribe(function() Refresh() end) end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local STATUS = {
    off = { "Off", "Turn it on to look for EllesmereUI's target frame.", "quiet" },
    waiting = { "Waiting for login", "EllesmereUI makes its frames when you log in.", "quiet" },
    combat = { "Waits for combat to end", "The artwork is put on the target frame as soon as combat ends.", "quiet" },
    ready = { "Attached", "Decorating EllesmereUI's target frame.", "ok" },
    absent = { "EllesmereUI not loaded", "EllesmereUI's unit frames are not loaded, so there is no frame to decorate. Nothing is drawn anywhere else.", "warn" },
    noFrame = { "No EllesmereUI target frame", "EllesmereUI is loaded but draws no target frame of its own (it can be set to use Blizzard's or none). Nothing is drawn anywhere else.", "warn" },
    incompatible = { "Not recognised", "Something named like EllesmereUI's target frame was found, but it is not a target frame TwichUI recognises (a different EllesmereUI version?). Nothing is drawn.", "warn" },
}

K.Page({
    key = "targetArt", name = "Target dragon artwork", order = 97, group = "addons",
    description = "A dragon on EllesmereUI's target frame for bosses, rares and elites, in the artwork you choose for each. Off until you turn it on.",
    keywords = "ellesmereui ellesmere unit frame target frame dragon elite rare boss world boss rare elite classification artwork decoration portrait silver gold wings",
    overview = {
        label = "Target dragon artwork", tip = "A dragon on EllesmereUI's target frame for bosses, rares and elites.",
        when = function() return R.TargetArt ~= nil end,
        status = function() return K.OnOff(On()) end,
    },
    when = function() return R.TargetArt ~= nil and R.TargetArtDisplay ~= nil end,
    host = function() return P.Frame() end, hostAfter = "Preview", hostHeight = HOST_H,
    build = function()
        local Header, Toggle, Under = K.Header, K.Toggle, K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local ta = TA()

        Header("Target dragon artwork", "Decorates EllesmereUI's target frame with a dragon chosen by the kind of enemy you target. It only draws: it never changes EllesmereUI's frame, its settings or what you can click, and draws nothing without EllesmereUI's own target frame.")
        local main = Toggle("targetArt", "Show dragon artwork on the target frame",
            "When your target is one of the kinds below, draws the artwork you chose for it at the target frame's corner. The kind comes from the game: its boss flag first, then its classification (world boss, rare elite, elite, rare). Ordinary enemies, players and anything the game won't say get none.\n\nNeeds EllesmereUI's unit frames with EllesmereUI's own target frame. Turn it off to remove it completely: nothing listens for the game's events and the artwork is hidden.")
        Under(K.Status("EllesmereUI target frame",
            function() return STATUS[D().Status()] and STATUS[D().Status()][1] or "Unknown" end,
            function() return STATUS[D().Status()] and STATUS[D().Status()][2] end,
            "Whether EllesmereUI's target frame was found. Read when this page is drawn; it is not polled. TwichUI looks for it at login, when you enter the world and when your target changes.",
            function() return STATUS[D().Status()] and STATUS[D().Status()][3] end), main, On)

        local resettable = {}
        local function Shared(key, varType, label, set)
            local setting = K.Proxy("targetArt" .. key:sub(1, 1):upper() .. key:sub(2), varType, label, ta.DEFAULTS[key],
                function() return ta.Get(key) end, set or function(value) ta.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = ta.DEFAULTS[key] } end
            return setting
        end
        local function Whole(key) return function(v) ta.Set(key, math.floor(v + 0.5)) end end
        local function Bool(key) return function(v) ta.Set(key, v and true or false) end end

        local hide = Under(K.Checkbox(Shared("hideEllesmere", BOOL, "Hide EllesmereUI's own target dragon while this one shows", Bool("hideEllesmere")),
            "EllesmereUI can draw a dragon of its own on the target (Elite Enemy Dragon, or the Elite/Rare Indicator's Pixels Dragon style). With this on, that dragon is made invisible while TwichUI's artwork shows, and comes back as soon as TwichUI's goes (another target, turning this off, or turning the artwork off). EllesmereUI's settings are not changed. The small Elite/Rare badge, and a dragon painted into a stock frame style, are left as they are."), main, On)
        K.Note(hide, function()
            local s = D().Snapshot()
            if ta.Get("hideEllesmere") and s.status == "ready" and not s.hasNative then
                return "EllesmereUI's own target dragon is not turned on there, so there is nothing to hide."
            end
        end)

        Header("Artwork for each kind of enemy", "Which artwork each kind of target gets. The kinds are the game's own, read when you change target. \"Boss\" is the game's boss flag and is checked first; an elite is never assumed to be a boss.")
        for _, k in ipairs(ta.KINDS) do
            local key = ta.MapKey(k[1])
            Under(K.Dropdown(Shared(key, STRING, k[2]), function() return k[1] == "boss" and ta.CHOICES.mapBoss or ta.CHOICES.map end, k[3]), main, On)
        end

        Header("Appearance", "One placement for all three artworks. Each is sized from your target frame's height and placed by its own crook, so they line up the same way. Changes show at once, in combat too.")
        local lim = ta.LIMITS
        Under(K.Slider(Shared("opacity", NUMBER, "Opacity", Whole("opacity")), lim.opacity[1], lim.opacity[2],
            "How solid the artwork is, in percent."), main, On)
        Under(K.Slider(Shared("scale", NUMBER, "Scale", Whole("scale")), lim.scale[1], lim.scale[2],
            "In percent. At 100% each dragon is as tall as it takes for its tail to reach the bottom of your target frame when its crook is on the frame's top corner, so it grows and shrinks with the frame. Its proportions are never changed."), main, On)
        Under(K.Dropdown(Shared("framePoint", STRING, "Point on the target frame"), function() return ta.CHOICES.framePoint end,
            "Where on EllesmereUI's target frame the artwork is placed. Top right, with the dragon's crook, wraps the dragon round the frame's corner, as the game's own elite dragon does."), main, On)
        Under(K.Dropdown(Shared("artPoint", STRING, "Point on the artwork"), function() return ta.CHOICES.artPoint end,
            "Which point of the artwork goes on the frame's point. The dragon's crook is the inside corner of its curve, between its head and its tail; each artwork has its own, so all three sit the same way. A corner or edge uses the artwork's outline instead."), main, On)
        Under(K.Slider(Shared("x", NUMBER, "Horizontal offset", Whole("x")), lim.x[1], lim.x[2],
            "Moves the artwork right (positive) or left, in the target frame's own units, so it keeps its place when the frame is scaled."), main, On)
        Under(K.Slider(Shared("y", NUMBER, "Vertical offset", Whole("y")), lim.y[1], lim.y[2],
            "Moves the artwork up (positive) or down, in the target frame's own units."), main, On)
        Under(K.Checkbox(Shared("mirror", BOOL, "Mirror the artwork", Bool("mirror")),
            "Draws the dragon facing the other way. Its crook moves to the other side with it, so for a dragon on the frame's left choose Top left as the point on the target frame."), main, On)
        Under(K.Dropdown(Shared("layer", STRING, "Draw it"), function() return ta.CHOICES.layer end,
            "In front of the frame draws over EllesmereUI's bars and text; at the default place the dragon sits outside the frame, so nothing is covered. Behind the frame draws under all of it, so only what reaches outside shows. It stays within the target frame's own layer either way and never takes the mouse."), main, On)

        Header("Preview", "See the artwork without finding a rare or a boss.")

        -- One artwork's own adjustment: the rows follow the artwork chosen in the preview above, so it can be watched.
        Header("Fine-tune each artwork", "Adjusts only the artwork chosen in the preview above, on top of the appearance settings, so one dragon can sit differently from the others. Choose another artwork in the preview to adjust it.")
        local function Shown() return D().PreviewArt() end
        local function ShownName() return ta.ART[Shown()].label end
        local function Tune(part, label, tooltip, varType, wrap)
            local setting = K.Proxy("targetArtTune" .. part, varType or NUMBER, label, ta.TUNE_DEFAULTS[part],
                function() return ta.Get(ta.TuneKey(Shown(), part)) end,
                function(v) ta.Set(ta.TuneKey(Shown(), part), wrap and wrap(v) or math.floor(v + 0.5)) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = ta.TUNE_DEFAULTS[part] } end
            local tl = ta.TUNE_LIMITS[part]
            local row = Under(K.Slider(setting, tl[1], tl[2], tooltip), main, On)
            K.Note(row, function() return "Adjusting: " .. ShownName() .. "." end)
            return row
        end
        Tune("X", "This artwork's horizontal offset", "Moves only this artwork right (positive) or left, in the target frame's own units, added to the shared horizontal offset.")
        Tune("Y", "This artwork's vertical offset", "Moves only this artwork up (positive) or down, in the target frame's own units, added to the shared vertical offset.")
        Tune("Scale", "This artwork's size", "Makes only this artwork bigger or smaller, in percent of the shared size. Its proportions are never changed.")
        local tuneReset = Under(K.Button("Put this artwork back", "Put back", function()
            local id = Shown()
            for part, default in pairs(ta.TUNE_DEFAULTS) do ta.Set(ta.TuneKey(id, part), default) end
            K.RefreshOverview()
        end, "Puts the artwork chosen in the preview back to its own default place and size (no adjustment). The other artworks and the shared settings are kept."), main, On)
        if tuneReset then tuneReset.reset = true end

        Header("Reset", "Puts this page's settings back to their defaults. Whether the artwork is on is kept.")
        K.ResetButton("Target dragon artwork settings", resettable, function() ta.ResetSettings() end,
            "Puts the artwork for each kind of enemy, the appearance, every artwork's own adjustment and the EllesmereUI dragon option back to their defaults. The switch is kept.")
    end,
})
