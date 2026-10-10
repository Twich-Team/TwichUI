-- TwichUI: frame appearance (broker menus, and the refreshments panel)
-- A look a player can set for some of TwichUI's own frames: background texture, color and opacity,
-- and border texture, thickness, color and opacity. R.MenuStyle is the look of every menu TwichUI
-- opens from a data bar launcher (Mage Travel, Mage Conjuring), saved in TwichUIDB.ui.brokerMenu;
-- MenuStyle.New(savedKey, defaults) makes another, separately saved look with the same choices
-- (the refreshments panel's, in TwichUIDB.ui.refreshmentsStyle). Only the values the player has
-- changed are saved, so a default can still be improved later. Not part of configuration sharing or
-- backups, like the rest of TwichUI's own settings.
-- Apply(frame) draws the look on a BackdropTemplate frame. The background and the border are the
-- backdrop's own pieces, each with its own color and alpha, so neither opacity touches the menu's
-- text, icons or buttons, or the other piece. Textures are named by a stable id, never a list
-- position:
--   "none"       nothing is drawn;
--   "solid"      a flat color (background) or a plain line (border);
--   "<name>"     one of the game's own textures listed in BUILTIN below, or any texture the
--                LibSharedMedia "background" / "border" lists have (any addon's, also ones added
--                after TwichUI loads);
--   "eui:<key>"  for a border, one of EllesmereUI's own border textures, such as Pixels Textured,
--                drawn by its own API through modules/Borders.lua as the Food and Drink buttons do;
--                for a background, one of the textures EllesmereUI offers for its own backgrounds
--                (its chat background, its bars: Melli, Plating, Glass, Pixels Background ...), read
--                from its EllesmereUI.BuildBarTextureTables. Listed and drawn only while EllesmereUI
--                is installed; nothing of its is copied;
--   "bar:<name>" (backgrounds only) a texture in LibSharedMedia's "statusbar" list, which
--                EllesmereUI also offers as backgrounds.
-- EllesmereUI's and the status bar textures are stretched over the frame and tinted by the color,
-- as EllesmereUI draws them; the game's and LibSharedMedia's backgrounds repeat.
-- A saved name that is no longer there is drawn as "solid" and stays saved and listed, marked
-- "(not available)", until the player picks.

local R = TwichUI

local WHITE = [[Interface\Buttons\WHITE8x8]]
local TILE = 64   -- how big a textured background is repeated, in pixels

-- The menus' defaults are the look they had before this was a setting: the Chronicle's umber
-- (a little lighter, as its popovers are) with a thin bronze line.
local MENU_DEFAULTS = {
    bgTexture = "solid", bgColor = "ff2b2117", bgOpacity = 100,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 95, borderSize = 1,
}
-- Border thickness is in screen pixels. A textured border needs a few to read at all, and a frame
-- keeps its text clear of a thick one, so the limit is modest.
local LIMITS = { bgOpacity = { 0, 100 }, borderOpacity = { 0, 100 }, borderSize = { 0, 16 } }

-- The game's own textures, by LibSharedMedia's usual names. Each path is one Blizzard's own
-- interface code (the Forever branch of the UI source) draws, so the client has it. Nothing is
-- copied from another addon.
local BUILTIN = {
    background = {
        { "Blizzard Tooltip", [[Interface\Tooltips\UI-Tooltip-Background]] },
        { "Blizzard Dialog Background", [[Interface\DialogFrame\UI-DialogBox-Background]] },
        { "Blizzard Dialog Background Dark", [[Interface\DialogFrame\UI-DialogBox-Background-Dark]] },
        { "Blizzard Marble", [[Interface\FrameGeneral\UI-Background-Marble]] },
        { "Blizzard Rock", [[Interface\FrameGeneral\UI-Background-Rock]] },
    },
    border = {
        { "Blizzard Tooltip", [[Interface\Tooltips\UI-Tooltip-Border]] },
        { "Blizzard Dialog", [[Interface\DialogFrame\UI-DialogBox-Border]] },
        { "Blizzard Dialog Gold", [[Interface\DialogFrame\UI-DialogBox-Gold-Border]] },
    },
}
local builtinPath = {}
for kind, list in pairs(BUILTIN) do
    builtinPath[kind] = {}
    for _, entry in ipairs(list) do builtinPath[kind][entry[1]] = entry[2] end
end

local function SharedMedia() return LibStub and LibStub("LibSharedMedia-3.0", true) end

local BAR_PREFIX = "bar:"
-- Names some media packs register as status bars that are icons, not textures (EllesmereUI leaves
-- them out of its lists too).
local NOT_TEXTURES = { play_icon = true, stop_icon = true, user_icon = true, users_icon = true }

local function BarName(id)
    if type(id) == "string" and id:sub(1, #BAR_PREFIX) == BAR_PREFIX then return id:sub(#BAR_PREFIX + 1) end
end

-- The textures EllesmereUI offers for its own backgrounds, read once it is loaded:
-- { path = { [key] = file }, list = { { "eui:<key>", name }, ... } } in its order, or nil without it.
local euiBackgrounds
local function EllesmereBackgrounds()
    local e = EllesmereUI
    if not (type(e) == "table" and type(e.BuildBarTextureTables) == "function") then return nil end
    if euiBackgrounds and euiBackgrounds.source == e then return euiBackgrounds end
    local ok, files, names, order = pcall(e.BuildBarTextureTables, true)
    if not (ok and type(files) == "table" and type(order) == "table") then return nil end
    local out = { source = e, path = {}, list = {} }
    for _, key in ipairs(order) do
        local file = files[key]
        if type(key) == "string" and key ~= "none" and type(file) == "string" and file ~= "" then
            out.path[key] = file
            local name = type(names) == "table" and names[key]
            out.list[#out.list + 1] = { R.Borders.EUI_PREFIX .. key, type(name) == "string" and name or key }
        end
    end
    euiBackgrounds = out
    return out
end

---------------------------------------------------------------------------
-- Values, colors and textures: the same for every look.
---------------------------------------------------------------------------
local function Valid(key, value)
    local limit = LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif key == "bgTexture" or key == "borderTexture" then return R.Borders.ValidName(value)
    elseif key == "bgColor" or key == "borderColor" then
        return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    end
    return false
end

-- "AARRGGBB" as r, g, b in 0-1. The alpha part is ignored: opacity is its own setting.
local function ParseColor(hex)
    if not Valid("bgColor", hex) then return nil end
    local function part(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
    return part(3), part(5), part(7)
end

-- The file for a texture id of a kind ("background" or "border"), and what became of it:
-- "ok", "none" (nothing to draw), "eui" (an EllesmereUI border, drawn by it; no file), or
-- "missing" (the saved name isn't available now; the plain line or color is drawn instead). The shared-media table is read directly rather than through
-- Fetch, which would hand back a global override for the whole kind.
-- A third result, true, means the texture is stretched over the frame rather than repeated.
local function Resolve(kind, id)
    if id == "none" or id == "None" then return nil, "none" end
    if id == "solid" then return WHITE, "ok" end
    local euiKey = R.Borders.EllesmereKey(id)
    if euiKey and kind == "border" then
        local e = R.Borders.Ellesmere()
        if e and e.ResolveBorderTexture(euiKey) then return nil, "eui" end
        return WHITE, "missing"
    end
    if euiKey then
        local eb = EllesmereBackgrounds()
        local file = eb and eb.path[euiKey]
        if file then return file, "ok", true end
        return WHITE, "missing"
    end
    local barName = kind == "background" and BarName(id)
    if barName then
        local LSM = SharedMedia()
        local list = LSM and LSM:HashTable("statusbar")
        local file = list and list[barName]
        if (type(file) == "string" and file ~= "") or (type(file) == "number" and file > 0) then return file, "ok", true end
        return WHITE, "missing"
    end
    local path = builtinPath[kind] and builtinPath[kind][id]
    if not path then
        local LSM = SharedMedia()
        local list = LSM and LSM:HashTable(kind)
        path = list and list[id]
    end
    if (type(path) == "string" and path ~= "") or (type(path) == "number" and path > 0) then return path, "ok" end
    return WHITE, "missing"
end

-- LibSharedMedia's own list carries Blizzard textures from other versions of the game, which
-- this client may not have; only the ones in BUILTIN are offered.
local function Offered(kind, name)
    if name == "None" or name == "Solid" or not R.Borders.ValidName(name) then return false end
    if builtinPath[kind][name] then return false end   -- listed first, from BUILTIN
    return not name:find("^Blizzard ")
end

-- { { id, label }, ... } for a texture choice of a kind: None, Solid, the game's own, EllesmereUI's
-- (borders, while it is installed), then every LibSharedMedia entry of that kind, sorted. The saved choice stays listed, marked, if it's gone.
local function Choices(kind, current)
    local list = { { "none", "None" }, { "solid", kind == "border" and "Solid line" or "Solid color" } }
    for _, entry in ipairs(BUILTIN[kind]) do list[#list + 1] = { entry[1], entry[1] } end
    local files = {}   -- files already listed, so the same texture isn't offered twice under two names
    if kind == "border" then
        for _, choice in ipairs(R.Borders.EllesmereChoices()) do
            if not builtinPath.border[choice[2]] then list[#list + 1] = choice end   -- not a name listed above
        end
    else
        local eb = EllesmereBackgrounds()
        for _, choice in ipairs(eb and eb.list or {}) do
            list[#list + 1] = choice
            files[eb.path[R.Borders.EllesmereKey(choice[1])]] = true
        end
    end
    local LSM = SharedMedia()
    local names = LSM and LSM:HashTable(kind)
    local sorted = {}
    for name in pairs(names or {}) do
        if Offered(kind, name) then sorted[#sorted + 1] = name end
    end
    table.sort(sorted)
    for _, name in ipairs(sorted) do list[#list + 1] = { name, name } end
    if kind == "background" then
        -- Status bar textures, as EllesmereUI offers them for its backgrounds.
        local bars = LSM and LSM:HashTable("statusbar")
        local labels, barNames = {}, {}
        for _, choice in ipairs(list) do labels[choice[2]] = true end
        for name, file in pairs(bars or {}) do
            if Offered(kind, name) and not NOT_TEXTURES[name] and not labels[name] and not files[file] then
                barNames[#barNames + 1] = name
            end
        end
        table.sort(barNames)
        for _, name in ipairs(barNames) do list[#list + 1] = { BAR_PREFIX .. name, name } end
    end
    for _, choice in ipairs(list) do if choice[1] == current then return list end end
    list[#list + 1] = { current, (R.Borders.EllesmereKey(current) or BarName(current) or current) .. " (not available)" }
    return list
end

-- UI units for some screen pixels at a frame's scale, so a 1-pixel line is one pixel at any UI
-- scale (a plain 1 is a blur or a skipped line at many scales).
local function Pixels(frame, pixels)
    if pixels <= 0 then return 0 end
    if PixelUtil and PixelUtil.ConvertPixelsToUIForRegion and GetPhysicalScreenSize then
        return PixelUtil.ConvertPixelsToUIForRegion(pixels, frame)
    end
    return pixels
end

---------------------------------------------------------------------------
-- One look, saved in TwichUIDB.ui[savedKey]. defaults: a value for each of bgTexture, bgColor,
-- bgOpacity, borderTexture, borderColor, borderOpacity and borderSize.
---------------------------------------------------------------------------
local function New(savedKey, defaults)
    local MS = { DEFAULTS = defaults, LIMITS = LIMITS, ParseColor = ParseColor, Resolve = Resolve, Choices = Choices }
    local rules = { defaultSize = defaults.borderSize, defaultColor = defaults.borderColor,
        solidMax = 4, texturedMin = 8, texturedSeed = 12, maxSize = LIMITS.borderSize[2] }

    local function Saved()
        local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui[savedKey]
        return type(saved) == "table" and saved or nil
    end

    -- Read through Get, which falls back to the default for anything invalid.
    function MS.Get(key)
        local saved = Saved()
        local value = saved and saved[key]
        if Valid(key, value) then return value end
        return defaults[key]
    end

    local subscribers = {}

    -- fn() is called after any of this look's settings changes (a frame or a preview redraws itself).
    function MS.Subscribe(fn) subscribers[#subscribers + 1] = fn end

    local function Notify()
        for _, fn in ipairs(subscribers) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end

    -- Saves one setting (an invalid value is refused) and redraws.
    function MS.Set(key, value)
        if not Valid(key, value) then return false end
        TwichUIDB.ui = TwichUIDB.ui or {}
        if type(TwichUIDB.ui[savedKey]) ~= "table" then TwichUIDB.ui[savedKey] = {} end
        local saved = TwichUIDB.ui[savedKey]
        -- a new border texture gets a thickness that suits it, unless the player set their own
        if key == "borderTexture" and value ~= "none" then
            local size, color = MS.Get("borderSize"), MS.Get("borderColor")
            local newSize, newColor = R.Borders.Reseed(MS.Get("borderTexture"), value, size, color, rules)
            if newSize ~= size then saved.borderSize = newSize end
            if newColor ~= color then saved.borderColor = newColor end
        end
        saved[key] = value
        Notify()
        return true
    end

    -- Puts this whole look back to its defaults; nothing else of TwichUI's is touched.
    function MS.Reset()
        if TwichUIDB and TwichUIDB.ui then TwichUIDB.ui[savedKey] = nil end
        Notify()
    end

    function MS.BackgroundChoices() return Choices("background", MS.Get("bgTexture")) end
    function MS.BorderChoices() return Choices("border", MS.Get("borderTexture")) end

    -- Media added after TwichUI loaded (another addon's pack): a saved choice that was waiting for
    -- it can now be drawn. The lists above are read afresh whenever a dropdown opens.
    R:OnInit(function()
        local LSM = SharedMedia()
        if not (LSM and LSM.RegisterCallback) then return end
        LSM.RegisterCallback(MS, "LibSharedMedia_Registered", function(_, kind, name)
            local bg = MS.Get("bgTexture")
            if (kind == "background" and name == bg) or (kind == "statusbar" and BAR_PREFIX .. name == bg)
                or (kind == "border" and name == MS.Get("borderTexture")) then
                Notify()
            end
        end)
    end)

    -- Draws the player's look on a BackdropTemplate frame: its backdrop (the background, and the
    -- border drawn inside the frame's edge) and, for the plain line, a faint highlight and shade just
    -- inside it as the Chronicle's popovers have. Only changes the frame's own pieces, never its
    -- children. Returns how far the border reaches in from the frame's edge, in UI units, so the
    -- caller can keep its content clear of it.
    function MS.Apply(frame)
        local bgPath, _, stretch = Resolve("background", MS.Get("bgTexture"))
        local borderName = MS.Get("borderTexture")
        local edgePath, edgeState = Resolve("border", borderName)
        local size = MS.Get("borderSize")
        local br, bg, bb = ParseColor(MS.Get("borderColor"))
        local alpha = MS.Get("borderOpacity") / 100

        -- EllesmereUI's border is drawn by it on a frame of ours; if it can't be, the plain line is
        local store = frame.twichBorders
        if not store then
            store = {}
            frame.twichBorders = store
        end
        if edgeState == "eui" and size > 0 then
            if R.Borders.Draw(store, frame, borderName, size, br, bg, bb, alpha) ~= "ellesmere" then
                edgePath, edgeState = WHITE, "missing"
            end
        else
            R.Borders.Hide(store)
        end
        local eui = edgeState == "eui" and size > 0

        local edge = (edgePath or eui) and Pixels(frame, size) or 0
        local line = edge > 0 and edgePath == WHITE

        local info = {}
        if bgPath then
            info.bgFile = bgPath
            info.tile = bgPath ~= WHITE and not stretch
            info.tileSize = info.tile and Pixels(frame, TILE) or nil
            -- a textured border's corners are rounded: keep the background off them
            local inset = (edge > 0 and not line and not eui) and math.floor(edge / 4) or 0
            info.insets = { left = inset, right = inset, top = inset, bottom = inset }
        end
        if edge > 0 and edgePath then info.edgeFile = edgePath end
        info.edgeSize = (edge > 0 and edgePath) and edge or 1
        frame:SetBackdrop(info)   -- with neither, this clears the backdrop

        local r, g, b = ParseColor(MS.Get("bgColor"))
        frame:SetBackdropColor(r, g, b, MS.Get("bgOpacity") / 100)
        frame:SetBackdropBorderColor(br, bg, bb, alpha)

        local bevel = frame.twichBevel
        if not bevel then
            bevel = { top = frame:CreateTexture(nil, "BORDER"), bottom = frame:CreateTexture(nil, "BORDER") }
            frame.twichBevel = bevel
        end
        local hair = Pixels(frame, 1)
        bevel.top:SetColorTexture(0.79, 0.64, 0.29, 0.14 * alpha)
        bevel.bottom:SetColorTexture(0, 0, 0, 0.45 * alpha)
        for _, side in ipairs({ "top", "bottom" }) do
            local t = bevel[side]
            local up = side == "top"
            t:ClearAllPoints()
            t:SetHeight(hair)
            t:SetPoint(up and "TOPLEFT" or "BOTTOMLEFT", edge, up and -edge or edge)
            t:SetPoint(up and "TOPRIGHT" or "BOTTOMRIGHT", -edge, up and -edge or edge)
            t:SetShown(line)
        end
        return edge
    end

    return MS
end

-- The broker menus' look, as it always was; New makes others.
local MS = New("brokerMenu", MENU_DEFAULTS)
MS.New = New
R.MenuStyle = MS
