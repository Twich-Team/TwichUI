-- TwichUI Layout Setup: the scene (what the preview shows, for one layout, one screen and one scenario)
-- No frames here. The scene is worked out from the engine and from nothing else, so the miniature (Preview.lua), the
-- full-size overlay (Overlay.lua) and the install cannot disagree about where anything goes:
--
--   * the components' rects are the resolved geometry itself (TwichUI_Layouts' Geometry.Resolve, the call LY.Plan makes
--     for the same variant, screen and density);
--   * the pieces inside them (unit frames, bars, cast bars, party frames, TwichUI's own markers) are TwichUI_Layouts'
--     LY.Elements for that geometry: the install's own position math, plus sample sizes (Elements.lua says which);
--   * what is drawn inside a component (chat lines, meter bars, objectives) and the tooltip are sample content, chosen by
--     the scenario. Their text is plain sample text, never anything from the player's game.
--
-- A scenario changes only what the sample shows (which pieces are visible, how much text there is); it never changes
-- where anything is, and it is not remembered: it is how the preview looks now, not a choice.
--
--   Scene.SCENARIOS        { { id, label, short, hint } } in the order the selector lists them
--   Scene.Scenario(id)     the entry, or the first
--   Scene.Build(layout, geo, opts) -> scene | nil, why
--     layout = { pkg, variant }; geo = Geometry.Resolve's result (or an update's final plan, Engine plan.final.geometry);
--     opts = { scenario = id, tooltip = { point, x, y }, moved = { [piece id] = the player's own place } (plan.final.moved) }
--     scene = { variant, scenario, screen = { w, h }, fits, geo, components = { { id, label, kind, rect, applied, troubled,
--       sample } }, elements = { { id, adapter, label, kind, comp, rect } }, hidden = n (pieces this scenario leaves out),
--       notes = { code, id }, tooltip = { rect, lines } | nil }

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local Scene = {}
WZ.Scene = Scene

Scene.SCENARIOS = {
    { id = "solo", label = "Solo", short = "Solo", hint = "Just you: your frame and bars, a little chat, a short quest list." },
    { id = "target", label = "Target selected", short = "Target", hint = "A target, its target and its cast bar, and your own cast bar." },
    { id = "party", label = "Dungeon party", short = "Party", hint = "A five-player party, a focus and a busy damage meter." },
    { id = "objectives", label = "Long objectives", short = "Long quests", hint = "A long quest list with long lines, to see how it wraps and whether it fits its box." },
    { id = "tooltip", label = "Tooltip visible", short = "Tooltip", hint = "A tooltip where the game puts one by default (EllesmereUI can move it)." },
}

function Scene.Scenario(id)
    for _, s in ipairs(Scene.SCENARIOS) do if s.id == id then return s end end
    return Scene.SCENARIOS[1]
end

-- Which scenarios show a piece. A piece not listed is always shown (bars, markers, your own frame).
local function Set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end return t end
local WHEN = {
    ["uf-target"] = Set("target", "party", "tooltip"), ["uf-targettarget"] = Set("target", "party", "tooltip"),
    ["uf-target-cast"] = Set("target"), ["rb-cast"] = Set("target", "party"), ["uf-player-cast"] = Set("target", "party"),
    ["uf-focus"] = Set("party"), ["uf-focus-cast"] = Set("party"), ["party-frames"] = Set("party"),
}

-- The sample content of a component, as data. Plain text: nothing here comes from the player's game.
local CHAT = {
    "Welcome to the sample world.", "A sample line of chat, to show where it lands.",
    "Another sample line, a little longer than the one before it.", "[Sample channel] Sample text.",
    "Yet another sample line of chat.", "The last sample line of chat.",
}
local METER = { { "Sample 1", 1 }, { "Sample 2", 0.82 }, { "Sample 3", 0.66 }, { "Sample 4", 0.5 }, { "Sample 5", 0.34 } }
local QUESTS_SHORT = {
    { title = "A sample quest", lines = { "Sample objective 1/3", "Sample objective 0/1" } },
}
local QUESTS_LONG = {
    { title = "A sample quest with a rather long title that has to wrap onto a second line",
        lines = { "Speak with the sample person standing beside the sample fountain in the middle of the sample town square",
            "Gather sixty-seven sample things from the sample hills to the north-east of the sample crossing: 12/67" } },
    { title = "Another long sample quest title, to see what a second quest does to the box",
        lines = { "Return to the sample outpost once the sample matter has been dealt with, and report to whoever is in charge there",
            "Defeat the sample creatures that roam the sample marshes at night: 4/9" } },
}
local TIP = { "Sample tooltip title", "A sample line of tooltip text.", "Another sample line, a little longer.", "A last sample line." }

local KIND = { central = "central", focus = "focus", chat = "chat", meter = "meter", minimap = "minimap",
    objectives = "objectives", notifications = "notifications" }
local TIP_W, TIP_H = 230, 96
Scene.TOOLTIP_FALLBACK = { point = "BOTTOMRIGHT", x = -9, y = 85 }   -- Forever's GameTooltipDefaultContainer (GameTooltip.xml)

local function Sample(kind, scenario)
    if kind == "chat" then
        local n = scenario == "party" and 6 or 4
        local lines = {}
        for i = 1, n do lines[i] = CHAT[i] end
        return { lines = lines }
    elseif kind == "meter" then
        local n = scenario == "party" and 5 or 3
        local rows = {}
        for i = 1, n do rows[i] = { name = METER[i][1], frac = METER[i][2] } end
        return { rows = rows }
    elseif kind == "objectives" then
        return { quests = scenario == "objectives" and QUESTS_LONG or QUESTS_SHORT, long = scenario == "objectives" }
    end
    return nil
end

function Scene.Build(layout, geo, opts)
    if type(geo) ~= "table" or not geo.components or not geo.screen then return nil, "no-geometry" end
    opts = opts or {}
    local scenario = Scene.Scenario(opts.scenario).id
    local scene = { variant = layout and layout.variant, scenario = scenario, geo = geo, fits = geo.fits,
        screen = { w = geo.screen.w, h = geo.screen.h }, components = {}, elements = {}, hidden = 0, notes = {} }

    local troubled = {}
    for _, d in ipairs(geo.diagnostics or {}) do
        if d.code == "overlap" or d.code == "offscreen" then troubled[d.id] = true if d.other then troubled[d.other] = true end end
    end
    for _, id in ipairs(geo.order) do
        local c = geo.components[id]
        if c.managed and c.rect.w > 0 and c.rect.h > 0 then
            local kind = KIND[id] or "box"
            scene.components[#scene.components + 1] = { id = id, label = c.label or id, kind = kind, rect = c.rect,
                applied = c.applied, troubled = troubled[id] or nil, sample = Sample(kind, scenario) }
        end
    end

    local pieces, notes = LY.Elements(layout.pkg, layout.variant, geo, opts.moved)   -- moved: the final plan's kept places
    scene.notes = notes
    for _, e in ipairs(pieces) do
        local when = WHEN[e.id]
        if not when or when[scenario] then scene.elements[#scene.elements + 1] = e else scene.hidden = scene.hidden + 1 end
    end

    if scenario == "tooltip" then
        local a = opts.tooltip or Scene.TOOLTIP_FALLBACK
        local P = LY.Geometry.POINTS[a.point] and a.point or Scene.TOOLTIP_FALLBACK.point
        local sx, sy = LY.Geometry.Point(geo.screen, P)
        scene.tooltip = { rect = LY.Geometry.Place(P, sx + (tonumber(a.x) or 0), sy + (tonumber(a.y) or 0), TIP_W, TIP_H), lines = TIP }
    end
    return scene
end
