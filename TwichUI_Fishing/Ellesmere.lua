-- TwichUI Fishing: EllesmereUI's interface, for Fishing Mode's fading (Stage 2)
-- Finds the frames EllesmereUI draws that Fishing Mode may fade, by role, from what EllesmereUI itself creates. Read
-- only: nothing in EllesmereUI is called, hooked, replaced or saved here; Fade.lua changes the alpha of what this file names
-- and nothing else (its policy is in that file's header).
--
-- What was read (EllesmereUI's public repository, EllesmereGaming/EllesmereUI, at 9.9.1, 2026-11-20; its .toc lists
-- interface 16001 and EllesmereUI_ClientGate.lua flags WoW Forever as supported, EllesmereUI.IS_FOREVER):
--   unit frames   every unit frame EllesmereUIUnitFrames spawns (player, target, focus, pet, target of target, focus target,
--                 boss) is parented to one frame, EllesmereUIUnitFrames_Hider, whose only job is a secure pet-battle
--                 visibility driver; EllesmereUI never writes its alpha (it writes the frames' own and the player's
--                 wrapper's). Fading that one frame fades every unit frame with no write EllesmereUI would undo, and its
--                 Show/Hide stays the driver's. 3D portraits (PlayerModel) do not inherit a parent's alpha (EllesmereUI says
--                 so where it mirrors their alpha), so each model under it is faded by itself.
--   action bars   EABBar_<key> for MainBar, Bar2..Bar10, StanceBar and PetBar (EUI_ActionBars_Bars.lua), the paging arrows'
--                 frame EABPagingFrame, the data bars EllesmereEAB_XPBar / RepBar / FavorBar, and the caps EllesmereUI paints
--                 on its micro menu and bag bar holders (EllesmereEAB_MicroBar / BagBar; the menu and the bags themselves are
--                 the game's MicroMenuContainer and BagsBar, which the game's own list fades). EllesmereUI writes these bars'
--                 alpha itself (mouse-over, Advanced Fade, visibility): Fade.lua's cover policy cooperates with that.
--   minimap       EllesmereUI takes the game's Minimap out of MinimapCluster (whose alpha it sets to 0), so the map is faded
--                 as Minimap. The engine draws the map's blips without regard to alpha (EllesmereUI notes it), so they may
--                 stay visible: partial.
--   group frames  EllesmereUIRaidFrameContainer (party and raid frames), and the resource bars, EllesmereUIResourceBarsFrame,
--                 with the unit frames.
--   panels        the player aura bars, EllesmereUIPlayerAuraBars_Buffs / _Debuffs, with the other optional panels.
-- Never touched: EllesmereUIMicroMenu and its buttons (EllesmereUI warns that an alpha change breaks their secure chain),
-- the extra action button and encounter bar (gameplay), and anything not listed.
-- Immersive overlays (cast bar and quest tracker) are included with fade.ellesmere, independent of optional aura panels.
-- Read again at EllesmereUI 9.9.3, d84a1e19 (2026-11-24): Resource Bars creates ERB_CastBarFrame under UIParent; its
-- SetElementVisibility writes alpha only at visibility edges. Forever's EUI_CustomQuestTracker is also under UIParent;
-- its SetAlpha hook forwards alpha to its separate secure item layer. The noncustom tracker uses ObjectiveTrackerFrame
-- plus EllesmereUIQTBackground. Alpha cover preserves all three owners' visibility/layout rules and settings.
--
-- Unverified in the real client: every name above comes from reading the source, not from a running game. A name that
-- does not exist (the module is off, or another version names it otherwise) is simply not faded, and the settings page and
-- /tui fish fade say which were found.
--
--   E.Detected()        true when EllesmereUI is loaded
--   E.Modules()         { { addon, label, loaded, version } } for the modules this file knows
--   E.Targets(groups)   { { name, group, role, label } } for the switched-on groups (only names that exist now)
--   E.Models(hider)     the 3D portrait models under the unit frames (a bounded walk of the hider's children)
--   E.Status()          what can be faded now, for people: { detected, version, forever, modules, found = { [group] = n } }

local R = TwichUI
local F = R.Fishing
local E = {}
F.Ellesmere = E

E.ADDON = "EllesmereUI"
E.HIDER = "EllesmereUIUnitFrames_Hider"
E.MODULES = {
    { addon = "EllesmereUIActionBars", label = "Action bars" },
    { addon = "EllesmereUIUnitFrames", label = "Unit frames" },
    { addon = "EllesmereUIMinimap", label = "Minimap" },
    { addon = "EllesmereUIRaidFrames", label = "Party and raid frames" },
    { addon = "EllesmereUIResourceBars", label = "Resource bars" },
    { addon = "EllesmereUIDamageMeters", label = "Damage meters" },
    { addon = "EllesmereUIQuestTracker", label = "Quest tracker" },
}
E.NEVER = { EllesmereUIMicroMenu = true, EllesmereEAB_ExtraActionButton = true, EllesmereEAB_EncounterBar = true }

local BAR_KEYS = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "Bar9", "Bar10", "StanceBar", "PetBar" }

-- Role lists: { name, group, role, label }.
local LIST = {
    { name = "ERB_CastBarFrame", group = "immersive", role = "castbar", label = "Player cast bar",
        module = "EllesmereUIResourceBars" },
    { name = "EUI_CustomQuestTracker", group = "immersive", role = "quest-tracker", label = "Quest tracker",
        module = "EllesmereUIQuestTracker" },
    { name = "ObjectiveTrackerFrame", group = "immersive", role = "quest-tracker", label = "Quest tracker (stock)",
        module = "EllesmereUIQuestTracker", requireModule = true },
    { name = "EllesmereUIQTBackground", group = "immersive", role = "quest-background", label = "Quest tracker background",
        module = "EllesmereUIQuestTracker" },
}
for _, key in ipairs(BAR_KEYS) do
    LIST[#LIST + 1] = { name = "EABBar_" .. key, group = "bars", role = "actionbar", label = "Action bar (" .. key .. ")",
        module = "EllesmereUIActionBars" }
end
for _, n in ipairs({ "EABPagingFrame", "EllesmereEAB_MicroBar", "EllesmereEAB_BagBar", "EllesmereEAB_XPBar", "EllesmereEAB_RepBar",
    "EllesmereEAB_FavorBar" }) do
    LIST[#LIST + 1] = { name = n, group = "bars", role = "bar-extra", label = n, module = "EllesmereUIActionBars" }
end
LIST[#LIST + 1] = { name = E.HIDER, group = "units", role = "unitframes", label = "Unit frames (all)", module = "EllesmereUIUnitFrames" }
LIST[#LIST + 1] = { name = "EllesmereUIResourceBarsFrame", group = "units", role = "resource", label = "Resource bars",
    module = "EllesmereUIResourceBars" }
LIST[#LIST + 1] = { name = "EllesmereUIRaidFrameContainer", group = "units", role = "group", label = "Party and raid frames",
    module = "EllesmereUIRaidFrames" }
LIST[#LIST + 1] = { name = "Minimap", group = "minimap", role = "minimap", label = "Minimap (its blips may stay)",
    module = "EllesmereUIMinimap" }
for _, n in ipairs({ "EllesmereUIPlayerAuraBars_Buffs", "EllesmereUIPlayerAuraBars_Debuffs" }) do
    LIST[#LIST + 1] = { name = n, group = "panels", role = "auras", label = "Player aura bars", module = "EllesmereUIUnitFrames" }
end
-- Damage meters: each window is a frame named EllesmereUIDMFrame<n> (EUI_DamageMeters_Window.lua; up to MAX_WINDOWS = 5). Its
-- owner writes its alpha only to 1 when it shows it (UpdateVisibility), which the cover policy handles like any other write.
for i = 1, 5 do
    LIST[#LIST + 1] = { name = "EllesmereUIDMFrame" .. i, group = "meters", role = "meter", label = "Damage meter " .. i,
        module = "EllesmereUIDamageMeters" }
end
-- The frame EllesmereUI parents the minimap to (its layout frame, which also carries the map's border and buttons), when
-- there is one: fading it fades the border and the pieces around the map with it. Never UIParent or the game's cluster.
local function MinimapHost()
    local mm = rawget(_G, "Minimap")
    if type(mm) ~= "table" or type(mm.GetParent) ~= "function" then return nil end
    local ok, p = pcall(mm.GetParent, mm)
    if not ok or type(p) ~= "table" or p == rawget(_G, "UIParent") or p == rawget(_G, "MinimapCluster") then return nil end
    if type(p.GetAlpha) ~= "function" or type(p.SetAlpha) ~= "function" then return nil end
    return p
end
E.MinimapHost = MinimapHost
LIST[#LIST + 1] = { name = "EllesmereUI minimap frame", group = "minimap", role = "minimap-host", label = "Minimap frame and border",
    module = "EllesmereUIMinimap", resolve = MinimapHost, optional = true }
E.LIST = LIST

local function Loaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) and true or false end
    return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
end

local function Version(name)
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
    if not meta then return nil end
    local ok, v = pcall(meta, name, "Version")
    v = ok and F.Readable(v) or nil
    return type(v) == "string" and v:sub(1, 24) or nil
end

function E.Detected()
    return Loaded(E.ADDON) and type(rawget(_G, "EllesmereUI")) == "table"
end

function E.Modules()
    local out = {}
    for i, m in ipairs(E.MODULES) do
        out[i] = { addon = m.addon, label = m.label, loaded = Loaded(m.addon), version = Version(m.addon) }
    end
    return out
end

local function IsRegion(f)
    return type(f) == "table" and type(f.GetAlpha) == "function" and type(f.SetAlpha) == "function"
end

-- The EllesmereUI frames that exist now for the switched-on groups (groups[g] true).
function E.Targets(groups)
    local out = {}
    if not E.Detected() then return out end
    for _, t in ipairs(LIST) do
        if groups[t.group] and (not t.requireModule or Loaded(t.module)) and not E.NEVER[t.name] and IsRegion(t.resolve and t.resolve() or rawget(_G, t.name)) then
            -- the game's Minimap is EllesmereUI's only while its minimap module runs; otherwise the game's own list has it
            if (t.role ~= "minimap" and t.role ~= "minimap-host") or Loaded(t.module) then out[#out + 1] = t end
        end
    end
    return out
end

-- The 3D models under the unit frames: a walk of the hider's children, at most MAX_WALK frames deep in all.
E.MAX_WALK = 400
local MODEL = { PlayerModel = true, Model = true, CinematicModel = true, DressUpModel = true }
function E.Models()
    local out = {}
    local root = rawget(_G, E.HIDER)
    if not (E.Detected() and type(root) == "table" and type(root.GetChildren) == "function") then return out end
    local seen, queue, n = {}, { root }, 0
    while #queue > 0 and n < E.MAX_WALK do
        local f = table.remove(queue)
        n = n + 1
        local ok, kids = pcall(function() return { f:GetChildren() } end)
        if ok then
            for _, k in ipairs(kids) do
                if type(k) == "table" and not seen[k] then
                    seen[k] = true
                    local okT, kind = pcall(k.GetObjectType, k)
                    if okT and MODEL[kind] and IsRegion(k) then out[#out + 1] = k
                    elseif type(k.GetChildren) == "function" then queue[#queue + 1] = k end
                end
            end
        end
    end
    E.walked = n
    return out
end

function E.Status()
    local found = { bars = 0, units = 0, minimap = 0, panels = 0, meters = 0, immersive = 0 }
    local all = { bars = true, units = true, minimap = true, panels = true, meters = true, immersive = true }
    for _, t in ipairs(E.Targets(all)) do found[t.group] = found[t.group] + 1 end
    local EUI = rawget(_G, "EllesmereUI")
    return {
        detected = E.Detected(), version = Version(E.ADDON),
        forever = type(EUI) == "table" and (EUI.IS_FOREVER == true or rawget(_G, "EUI_CLIENT_FOREVER") == true) or false,
        modules = E.Modules(), found = found,
    }
end
