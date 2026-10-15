-- TwichUI: configuration sharing, TwichUI's own settings
--
-- Setup sharing (Setups.lua, Share.lua) carries other addons' saved settings tables. TwichUI's own data is never
-- one of those (a name starting TwichUI is refused wherever a table could arrive). This file is the one place that
-- says which of TwichUI's own settings travel, as a part of a setup of its own beside the EllesmereUI profile:
--
--   pack.twichui = { schema, status, made, addon, groups = { [group] = { [slot] = { [key] = value } } },
--                    unknown, rejected }
--
-- Nothing here walks saved variables to decide what a setting is. The schema below names every shared setting
-- (its group, where it is kept, its kind and range); a feature's own DEFAULTS and LIMITS supply the numbers, so the
-- two cannot drift apart (tests/test_twichui_share.lua checks that every shared and every kept-local setting is
-- accounted for). What stays on this computer is listed in TC.LOCAL, each with its reason.
--
-- Scope. Almost everything is the profile in use (Profiles.lua): it is exported as the effective values, and an
-- import changes the profile this character is using (or a new copy of it, if asked). A few entries are
-- account-wide (the settings window's motion preference, stat weights): they are marked so, exported as they are
-- and applied account-wide. Nothing per character (talent tree choices, the waypoint each character placed) and
-- nothing that identifies a character travels.
--
-- Applying: the whole import is checked first (group by group; a group with any value this version cannot use is
-- skipped whole), then written with plain assignments, then the features are told once through Profiles.Refresh
-- (the same steps as a profile change). The values it replaced are kept as one Undo copy in TwichUIDB.setup.
-- Nothing is run: data is read as data and only fields named here are ever written.

local R = TwichUI
local ST = R.Setups
local TC = {}
R.TwichConfig = TC

TC.SCHEMA = 1          -- the shape of pack.twichui. Not the addon's version, TwichUIDB.schema or a pack's format.

-- Bounds on what is accepted from outside. A genuine entry is a few hundred values.
TC.LIMITS = { values = 1000, units = 96, stats = 48, ranked = 16, name = 100, sound = 64, weight = 1000, line = 9999999,
    classes = 24, addon = 40 }
local L = TC.LIMITS

---------------------------------------------------------------------------
-- What stays on this computer, and why. Every key TwichUI saves is either in a group below or here (a test
-- checks it, so a setting added later has to be placed). A path names a key; an entry also covers everything
-- under it.
---------------------------------------------------------------------------
TC.STAYS = {
    { code = "acts", text = "Anything that acts for you in the game: selling, filling trades by itself, accepting summons, resurrections or duels, releasing your spirit, and placing the waypoint. These only turn on by your own choice." },
    { code = "network", text = "What TwichUI sends to or accepts from other players: configuration sharing, accepting setups, the group check, how you send, and whether Party pins are on." },
    { code = "place", text = "Where windows, cards and buttons sit: that stays as you placed it on this screen." },
    { code = "other", text = "RestedXP's on/off switch (it chooses RestedXP's own theme), records of this character, map pins, the Journey Chronicle, backups, Undo copies and the setups you have received." },
}

TC.LOCAL = {
    -- acts for you
    ["modules.mageSell"] = "acts", ["modules.mageSellFood"] = "acts", ["modules.mageSellDrink"] = "acts",
    ["modules.mageSellDryRun"] = "acts", ["modules.mageRefreshmentsAutoFill"] = "acts",
    ["modules.qolSummons"] = "acts", ["modules.qolResurrect"] = "acts", ["modules.qolResurrectCombat"] = "acts",
    ["modules.qolReleasePvP"] = "acts", ["modules.qolDuels"] = "acts", ["modules.qolDuelsToDeath"] = "acts",
    ["modules.qolGuideWaypoint"] = "acts", ["modules.qolMageConjureFoodDrink"] = "acts",
    ["ui.qol"] = "acts", ["ui.mageSell"] = "acts", ["ui.guideWaypoint"] = "acts",
    -- sent to or accepted from other players
    ["modules.setupSharing"] = "network", ["modules.acceptSetups"] = "network", ["modules.groupCheck"] = "network",
    ["modules.partyPins"] = "network", ["shareTransport"] = "network",
    -- where things sit
    ["modules.foodDrinkUnlock"] = "place", ["ui.foodDrinkPosition"] = "place", ["ui.trainingPosition"] = "place",
    ["ui.welcomeBackPlace"] = "place", ["ui.friendLoginPlace"] = "place", ["ui.settingsWindow"] = "place",
    ["ui.refreshments.position"] = "place", ["ui.partyPins.position"] = "place",
    -- the rest
    ["modules.restedxpSkin"] = "other", ["modules.qolTwichUISettingsButton"] = "other",
    ["ui.restedxpSkinState"] = "other", ["ui.showAdvanced"] = "other", ["gear.trees"] = "other",
    ["ui.easyFishingClient"] = "other",
    ["pins"] = "other", ["setup"] = "other", ["storedData"] = "other", ["whisperProbe"] = "other", ["welcome"] = "other",
    ["schema"] = "other", ["migrated"] = "other", ["heldStored"] = "other",
    ["profiles"] = "other", ["profileKeys"] = "other", ["profileState"] = "other",
}

---------------------------------------------------------------------------
-- Kinds of value: what each may be
---------------------------------------------------------------------------
local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function PlainText(v, max) return type(v) == "string" and #v >= 1 and #v <= max and not v:find("[%c|]") end

local KIND = {
    bool = function(_, v) return type(v) == "boolean" end,
    int = function(f, v) return Whole(v) and v >= f.min and v <= f.max end,
    enum = function(f, v) return type(v) == "string" and f.values[v] == true end,
    color = function(_, v) return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil end,
    name = function(_, v) return PlainText(v, L.name) end,     -- a font or texture, by its name
    sound = function(_, v) return PlainText(v, L.sound) end,
}

local function Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local ENUM = {
    outline = Set({ "none", "outline", "thick" }),
    notifyOutline = Set({ "shadow", "none", "outline", "thick" }),
    layout = Set({ "horizontal", "vertical" }),
    buttonStyle = Set({ "filled", "outline" }),
    density = Set({ "comfortable", "compact" }),
    tiling = Set({ "auto", "tile", "stretch" }),
    labels = Set({ "hover", "always" }),
    minimapLabels = Set({ "off", "hover", "always" }),
    clicks = Set({ "alt", "altshift", "altright", "none" }),
    barText = Set({ "count", "number", "label", "none" }),
    channel = Set({ "SFX", "Dialog", "Ambience", "Master" }),
    footer = Set({ "subtle", "hidden", "normal" }),
    dividers = Set({ "subtle", "full" }),
    scrollbar = Set({ "slim", "original" }),
    stepLabel = Set({ "step", "total", "percent", "both" }),
    timeOutline = Set({ "inherit", "none", "outline", "thick" }),
    gradient = Set({ "none", "horizontal", "vertical" }),
    shape = Set({ "round", "square" }),
    reveal = Set({ "compare", "alt", "ctrl", "always" }),
    strictness = Set({ "cautious", "balanced", "eager" }),
    bagStyle = Set({ "gilded", "green", "badge" }),
    clock = Set({ "12", "24" }),
    gives = Set({ "share", "owed" }),
    sellMode = Set({ "direct", "ellesmere" }),
}

---------------------------------------------------------------------------
-- The schema. Built when first needed (the features are all loaded by then, and nothing is built at login).
-- A group whose feature is not there, or whose registry lacks something a field needs, is marked incomplete and
-- shares nothing, rather than sharing part of itself.
---------------------------------------------------------------------------
local function NewGroup(id, label, opts)
    return { id = id, label = label, page = opts and opts.page, note = opts and opts.note, scope = (opts and opts.scope) or "profile",
        fields = {}, index = {}, complete = true }
end

local function AddField(g, f)
    f.group = g.id
    f.scope = f.scope or g.scope
    g.fields[#g.fields + 1] = f
    g.index[f.slot] = g.index[f.slot] or {}
    g.index[f.slot][f.key] = f
end

local function Switches(g, keys)
    for _, key in ipairs(keys) do
        local d = R.DEFAULT_MODULES and R.DEFAULT_MODULES[key]
        if type(d) ~= "boolean" then g.complete = false
        else AddField(g, { slot = "modules", at = { "modules" }, key = key, kind = "bool", default = d, switch = true }) end
    end
end

-- One saved table: keys named explicitly; each key's default and range come from the feature's own registry.
-- at: where it is kept under TwichUIDB. enums: { [key] = set }. kinds: { [key] = "sound" } where a text is not a plain name.
local function Table(g, at, source, keys, enums, kinds, slot)
    local defaults = type(source) == "table" and source.DEFAULTS
    local limits = type(source) == "table" and source.LIMITS or {}
    if type(defaults) ~= "table" then g.complete = false return end
    for _, key in ipairs(keys) do
        local d = defaults[key]
        local f = { slot = slot or at[#at], at = at, key = key, default = d }
        local kind = kinds and kinds[key]
        if d == nil then
            g.complete = false
        elseif kind then
            f.kind = kind
        elseif type(d) == "boolean" then
            f.kind = "bool"
        elseif type(d) == "number" then
            local lim = limits[key]
            if type(lim) ~= "table" then g.complete = false else f.kind, f.min, f.max = "int", lim[1], lim[2] end
        elseif type(d) == "string" then
            local e = enums and enums[key]
            if e then f.kind, f.values = "enum", e
            elseif d:match("^%x%x%x%x%x%x%x%x$") then f.kind = "color"
            else f.kind = "name" end
        else
            g.complete = false
        end
        if f.kind then AddField(g, f) end
    end
end

-- One value of its own, kept at at[key].
local function Scalar(g, at, key, kind, default, extra)
    local f = { slot = at[#at], at = at, key = key, kind = kind, default = default }
    for k, v in pairs(extra or {}) do f[k] = v end
    if default == nil or (kind == "enum" and type(f.values) ~= "table") then g.complete = false return end
    AddField(g, f)
end

local LOOK = { "bgTexture", "bgColor", "bgOpacity", "borderTexture", "borderColor", "borderOpacity", "borderSize" }
local LOOK_TILED = { "bgTexture", "bgColor", "bgOpacity", "bgTiling", "bgTileSize", "bgInset",
    "borderTexture", "borderColor", "borderOpacity", "borderSize" }
local LOOK_ENUMS = { bgTiling = ENUM.tiling }

local function ChoiceSet(list)   -- { { key, label }, ... } -> set of keys
    local s = {}
    for _, c in ipairs(type(list) == "table" and list or {}) do if type(c) == "table" and type(c[1]) == "string" then s[c[1]] = true end end
    return s
end

---------------------------------------------------------------------------
-- Stat weights: the one group that is not flat. By class and talent tree, account-wide.
---------------------------------------------------------------------------
local Weights = {}

local function StatSets()
    local W = R.GearWeights
    if not (W and type(W.EDITOR) == "table" and type(W.ITEM_POINT) == "table") then return nil end
    local all = {}
    for _, group in ipairs(W.EDITOR) do
        for _, stat in ipairs(group[2]) do all[stat] = true end
    end
    local ranked = {}
    for stat in pairs(W.ITEM_POINT) do ranked[stat] = true end
    return all, ranked
end

local function ValidClass(c) return type(c) == "string" and #c >= 1 and #c <= 24 and c:match("^%u+$") ~= nil end
local function ValidLine(n) return Whole(n) and n >= 1 and n <= L.line end

-- A unit's three parts, each validated; nil, reason when one is unusable. Returns { weights, priority, use }.
local function CleanUnit(raw, all, ranked)
    local out = {}
    local n = 0
    if raw.weights ~= nil then
        if type(raw.weights) ~= "table" then return nil end
        out.weights = {}
        for stat, w in pairs(raw.weights) do
            n = n + 1
            if n > L.stats or type(stat) ~= "string" or not all[stat] or not Finite(w) or w < 0 or w > L.weight then return nil end
            out.weights[stat] = w
        end
        if next(out.weights) == nil then out.weights = nil end
    end
    if raw.priority ~= nil then
        if type(raw.priority) ~= "table" then return nil end
        local list, seen, count = {}, {}, 0
        for k in pairs(raw.priority) do
            count = count + 1
            if type(k) ~= "number" or count > L.ranked then return nil end
        end
        for i = 1, count do
            local stat = raw.priority[i]
            if type(stat) ~= "string" or not ranked[stat] or seen[stat] then return nil end
            seen[stat] = true
            list[i] = stat
        end
        if #list > 0 then out.priority = list end
    end
    if raw.use ~= nil then
        if type(raw.use) ~= "boolean" then return nil end
        out.use = raw.use == true or nil
    end
    if not (out.weights or out.priority or out.use) then return nil end
    return out
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- The live tables, as units: { ["CLASS:line"] = { class, line, weights, priority, use } }.
local function LiveUnits()
    local gear = type(TwichUIDB) == "table" and type(TwichUIDB.gear) == "table" and TwichUIDB.gear or {}
    local units = {}
    local function Unit(class, line)
        local key = class .. ":" .. line
        units[key] = units[key] or { class = class, line = line }
        return units[key]
    end
    for field, name in pairs({ weights = "weights", priority = "priority", use = "usePriority" }) do
        local all = gear[name]
        if type(all) == "table" then
            for class, byClass in pairs(all) do
                if ValidClass(class) and type(byClass) == "table" then
                    for line, value in pairs(byClass) do
                        if ValidLine(line) and value ~= nil then Unit(class, line)[field] = value end
                    end
                end
            end
        end
    end
    return units
end

function Weights.export()
    local all, ranked = StatSets()
    if not all then return nil end
    local list = {}
    for _, u in pairs(LiveUnits()) do
        local clean = CleanUnit(u, all, ranked)
        if clean then
            clean.class, clean.line = u.class, u.line
            list[#list + 1] = clean
        end
    end
    table.sort(list, function(a, b) if a.class ~= b.class then return a.class < b.class end return a.line < b.line end)
    if #list > L.units then
        for i = #list, L.units + 1, -1 do list[i] = nil end
    end
    if #list == 0 then return nil end
    return { units = list }
end

-- raw is what arrived. Returns the cleaned group, the number of values, or nil, reason.
function Weights.clean(raw)
    if type(raw) ~= "table" or type(raw.units) ~= "table" then return nil, "shape" end
    local all, ranked = StatSets()
    if not all then return nil, "feature" end
    local out, n, seen = {}, 0, {}
    for k in pairs(raw.units) do
        if type(k) ~= "number" then return nil, "shape" end
        n = n + 1
        if n > L.units then return nil, "too-large" end
    end
    local values = 0
    for i = 1, n do
        local u = raw.units[i]
        if type(u) ~= "table" or not ValidClass(u.class) or not ValidLine(u.line) then return nil, "invalid" end
        local key = u.class .. ":" .. u.line
        if seen[key] then return nil, "invalid" end
        seen[key] = true
        local clean = CleanUnit(u, all, ranked)
        if not clean then return nil, "invalid" end
        clean.class, clean.line = u.class, u.line
        out[#out + 1] = clean
        values = values + 1
        for _ in pairs(clean.weights or {}) do values = values + 1 end
        values = values + (clean.priority and #clean.priority or 0)
    end
    if #out == 0 then return nil, "empty" end
    return { units = out }, values
end

-- The units that applying would change here: { { class, line, what } }.
function Weights.plan(clean)
    local live = LiveUnits()
    local changes = {}
    for _, u in ipairs(clean.units) do
        local cur = live[u.class .. ":" .. u.line] or {}
        local diff = {}
        if not Same(u.weights, cur.weights) then diff[#diff + 1] = "stat weights" end
        if not Same(u.priority, cur.priority) then diff[#diff + 1] = "stat ranking" end
        if (u.use or false) ~= (cur.use or false) then diff[#diff + 1] = "weighing by ranking" end
        if #diff > 0 then changes[#changes + 1] = { class = u.class, line = u.line, what = table.concat(diff, ", ") } end
    end
    return changes
end

local function Gear()
    if type(TwichUIDB.gear) ~= "table" then TwichUIDB.gear = {} end
    local gear = TwichUIDB.gear
    for _, k in ipairs({ "weights", "priority", "usePriority" }) do
        if type(gear[k]) ~= "table" then gear[k] = {} end
    end
    return gear
end

local function WriteUnit(class, line, weights, priority, use)
    local gear = Gear()
    local function Put(name, value)
        local byClass = gear[name][class]
        if type(byClass) ~= "table" then
            if value == nil then return end
            byClass = {}
            gear[name][class] = byClass
        end
        byClass[line] = value
        if next(byClass) == nil then gear[name][class] = nil end
    end
    Put("weights", weights)
    Put("priority", priority)
    Put("usePriority", use)
end

-- Records what the changed units hold now, and puts the shared ones in place. Returns the undo records.
function Weights.apply(clean, plan)
    local live = LiveUnits()
    local changed = {}
    for _, c in ipairs(plan) do changed[c.class .. ":" .. c.line] = true end
    local undo = {}
    for _, u in ipairs(clean.units) do
        local key = u.class .. ":" .. u.line
        if changed[key] then
            local cur = live[key] or {}
            undo[#undo + 1] = { class = u.class, line = u.line, w = Copy(cur.weights), p = Copy(cur.priority), u = cur.use and true or nil }
            WriteUnit(u.class, u.line, Copy(u.weights), Copy(u.priority), u.use)
        end
    end
    return undo
end

function Weights.restore(records)
    local n = 0
    for _, r in ipairs(records) do
        if type(r) == "table" and ValidClass(r.class) and ValidLine(r.line) then
            WriteUnit(r.class, r.line, type(r.w) == "table" and Copy(r.w) or nil, type(r.p) == "table" and Copy(r.p) or nil, r.u == true or nil)
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- The groups
---------------------------------------------------------------------------
local schema   -- built once everything it needs was there

local function Define()
    local groups = {}
    local function Group(id, label, opts)
        local g = NewGroup(id, label, opts)
        groups[#groups + 1] = g
        return g
    end
    local g

    g = Group("general", "General", { page = "overview" })
    Switches(g, { "media", "quietLogin" })
    Scalar(g, { "ui" }, "reduceSettingsMotion", "bool", false, { scope = "account" })

    g = Group("notifications", "Notifications", { page = "notifications" })
    Switches(g, { "arrival", "arrivalSubzones", "arrivalDungeons", "arrivalReducedMotion", "trainingNotice",
        "friendLogin", "friendLoginSound" })
    do
        local A, F = R.Arrival, R.FriendLogin
        local holds = {}
        for _, h in ipairs(A and A.HOLDS or {}) do holds[h.key] = true end
        Scalar(g, { "ui" }, "arrivalHold", "enum", A and A.HOLD_DEFAULT, { values = holds })
        Scalar(g, { "ui" }, "friendLoginChannel", "enum", F and F.CHANNEL_DEFAULT, { values = ENUM.channel })
        Scalar(g, { "ui" }, "friendLoginChime", "sound", F and F.SOUND_DEFAULT)
        Scalar(g, { "ui" }, "previewSounds", "bool", false)
    end

    g = Group("notificationLook", "Notification appearance", { page = "notificationsLook",
        note = "Fonts, colors, opacity and backdrop of the notification cards: the shared look, and any card's own. Previews are never shared." })
    do
        local NL = R.NotifyLook
        if NL then
            for _, scope in ipairs({ "shared", "arrival", "training", "friend", "welcome" }) do
                local keys = {}
                for _, key in ipairs(NL.Keys(scope)) do keys[#keys + 1] = key end
                if scope ~= "shared" then keys[#keys + 1] = "own" end
                Table(g, { "ui", NL.SAVED[scope] }, NL.Source(scope), keys, { outline = ENUM.notifyOutline })
            end
        else
            g.complete = false
        end
    end

    g = Group("qol", "Quality of life", { page = "qol",
        note = "Only the Quick Keybind button and the Easy Fishing switch are shared. The automatic ones (summons, resurrection, release, duels, the waypoint) stay yours, and so do Easy Fishing's key and its permission to adjust the game's interaction settings: key bindings and game settings are never sent." })
    Switches(g, { "qolQuickKeybind", "qolEasyFishing" })

    g = Group("food", "Food and drink", { page = "food" })
    Switches(g, { "foodDrink", "foodDrinkFood", "foodDrinkDrink" })
    Table(g, { "ui", "foodDrink" }, R.FoodDrink, { "size", "spacing", "layout", "borderTexture", "borderSize", "borderColor",
        "borderClass", "borderOpacity", "zoom", "showCount", "buttonOpacity", "mouseover", "idleOpacity", "preferConjured" },
        { layout = ENUM.layout })

    g = Group("auction", "Auction House", { page = "auction" })
    Switches(g, { "auctionPosting" })

    g = Group("chronicle", "Journey Chronicle", { page = "chronicle",
        note = "Which events are written down and how the window reads. The entries and notes themselves are never shared." })
    Switches(g, { "chronicle", "chronicleLevels", "chronicleZones", "chronicleBosses", "chronicleDeaths", "chronicleGold",
        "chronicleRiding", "chronicleProfessions", "chronicleSound", "chronicleChat", "welcomeBack" })
    Scalar(g, { "ui" }, "chronicleClock", "enum", "12", { values = ENUM.clock })

    g = Group("chronicleLook", "Chronicle appearance", { page = "chronicleLook" })
    do
        local A, MS = R.ChronicleAppearance, R.MenuStyle
        Table(g, { "ui", "chronicleLook" }, A and MS and { DEFAULTS = A.LOOK_DEFAULTS, LIMITS = MS.LIMITS } or nil, LOOK_TILED, LOOK_ENUMS)
        Table(g, { "ui", "chronicleAppearance" }, A, { "worn", "headerColor", "listColor", "accentColor", "dividerColor",
            "showDividers", "hoverOpacity", "buttonStyle", "scrollThumbColor", "scrollTrackColor", "font", "headingFont",
            "outline", "customSizes", "titleSize", "headingSize", "bodySize", "metaSize", "titleColor", "headingColor",
            "bodyColor", "metaColor", "textOpacity", "lineSpacing", "padding", "windowOpacity" },
            { buttonStyle = ENUM.buttonStyle, outline = ENUM.outline })
    end

    g = Group("pins", "Party pins", { page = "pins",
        note = "Whether Party pins are on stays yours; how they behave, sound and show is shared. Your pins themselves are never shared." })
    do
        local PL = R.PinsLook
        Table(g, { "ui", "partyPins" }, PL and { DEFAULTS = PL.PREF_DEFAULTS } or nil,
            { "localClick", "partyClick", "labels", "minimap", "minimapLabels", "wayAlso" },
            { localClick = ENUM.clicks, partyClick = ENUM.clicks, labels = ENUM.labels, minimapLabels = ENUM.minimapLabels })
        Table(g, { "ui", "pinsBroker" }, PL and PL.Bar, { "text", "icon", "customColor", "color", "flash", "flashSeconds", "flashColor" },
            { text = ENUM.barText })
        Table(g, { "ui", "pinsSound" }, PL and PL.Sound, { "enabled", "sound", "channel" }, { channel = ENUM.channel }, { sound = "sound" })
        -- The two clicks never share a pin: the same rule the setter keeps.
        g.check = function(vals)
            local p = vals.partyPins
            if p and p.localClick and p.partyClick and p.localClick ~= "none" and p.localClick == p.partyClick then return false end
            return true
        end
    end

    g = Group("pinsLook", "Pin appearance", { page = "pinsLook" })
    do
        local PL = R.PinsLook
        Table(g, { "ui", "pinsAppearance" }, PL, { "font", "textSize", "accentColor", "density" }, { density = ENUM.density })
        Table(g, { "ui", "pinsMapText" }, PL and PL.MapText, { "font", "size", "color", "outline", "shadow" }, { outline = ENUM.outline })
        Table(g, { "ui", "pinsLook" }, PL and PL.Look, LOOK, LOOK_ENUMS)
        Table(g, { "ui", "pinsBrokerMenu" }, PL and PL.MenuLook, LOOK, LOOK_ENUMS)
        Table(g, { "ui", "pinsEditorLook" }, PL and PL.EditorLook, LOOK, LOOK_ENUMS)
    end

    g = Group("gear", "Gear comparison", { page = "gear" })
    Switches(g, { "gearHints", "gearBagIcons" })
    Table(g, { "gear" }, R.GearPrefs, { "glancePossible", "futureLevels", "reveal", "strictness", "bagStyle" },
        { reveal = ENUM.reveal, strictness = ENUM.strictness, bagStyle = ENUM.bagStyle })

    g = Group("gearWeights", "Gear stat weights", { page = "statWeights", scope = "account",
        note = "Kept by class and talent tree, for every profile. An entry for a class you don't play is stored and used when you do." })
    g.custom = Weights

    g = Group("mage", "Mage", { page = "mage",
        note = "Used when you play a Mage; the settings are stored either way. Selling and filling trades by itself stay yours: whether they are on, Dry run and your never-sell list never travel. How selling is handled (sell directly, or mark as junk with EllesmereUI) does; marking waits for your own confirmation on this computer." })
    Switches(g, { "mageTravel", "mageConjure", "mageRefreshments", "mageRefreshmentsTrade" })
    do
        local MT, MC, RB, RT, RF, RP = R.MageTravel, R.MageConjure, R.RefreshmentsBroker, R.RefreshmentsTrade, R.Refreshments, R.RefreshmentsPanel
        Scalar(g, { "ui" }, "mageTravelText", "enum", MT and MT.DEFAULT_TEXT, { values = ChoiceSet(MT and MT.TEXTS) })
        Scalar(g, { "ui" }, "mageConjureText", "enum", MC and MC.DEFAULT_TEXT, { values = ChoiceSet(MC and MC.TEXTS) })
        Scalar(g, { "ui" }, "refreshmentsText", "enum", RB and RB.DEFAULT_TEXT, { values = ChoiceSet(RB and RB.TEXTS) })
        Scalar(g, { "ui" }, "refreshmentsTradeGives", "enum", RT and RT.DEFAULT_GIVES, { values = ENUM.gives })
        local SL = R.MageSell
        Scalar(g, { "ui" }, "mageSellMode", "enum", SL and SL.DEFAULT_MODE, { values = ENUM.sellMode })
        local MS = R.MenuStyle
        Table(g, { "ui", "brokerMenu" }, MS, LOOK, LOOK_ENUMS)
        Table(g, { "ui", "refreshmentsStyle" }, RP and RP.Style, LOOK, LOOK_ENUMS)
        if RF and type(RF.CLASSES) == "table" and type(RF.CONTEXTS) == "table" and type(RF.KINDS) == "table"
            and type(RF.DEFAULTS) == "table" and type(RF.RESERVE_DEFAULT) == "table" and Whole(RF.MAX) then
            for _, context in ipairs(RF.CONTEXTS) do
                for _, class in ipairs(RF.CLASSES) do
                    for _, kind in ipairs(RF.KINDS) do
                        AddField(g, { slot = context .. "." .. class, at = { "ui", "refreshments", context, class }, key = kind,
                            kind = "int", min = 0, max = RF.MAX, default = RF.DEFAULTS[class] and RF.DEFAULTS[class][kind] or 0 })
                    end
                end
            end
            for _, kind in ipairs(RF.KINDS) do
                AddField(g, { slot = "reserve", at = { "ui", "refreshments", "reserve" }, key = kind, kind = "int", min = 0,
                    max = RF.MAX, default = RF.RESERVE_DEFAULT[kind] or 0 })
            end
        else
            g.complete = false
        end
    end

    g = Group("skins", "Addon skins", { page = "skins",
        note = "Each needs its addon, and takes effect after a reload." })
    Switches(g, { "attuneSkin", "auctionatorSkin", "foreverDungeonJournalSkin", "whatsTrainingSkin" })

    g = Group("restedxp", "RestedXP guide window", { page = "restedxp",
        note = "The look only. Whether the skin is on stays yours: turning it on chooses RestedXP's own theme. Needs RestedXP." })
    do
        local Sk = R.RestedXPSkin
        Table(g, { "ui", "restedxpSkin" }, Sk and Sk.Look, LOOK, LOOK_ENUMS)
        Table(g, { "ui", "restedxpSkinText" }, Sk and Sk.Text, { "titleFont", "titleOutline", "titleColor", "bodyFont", "bodyOutline",
            "bodyColor", "tintScrollbar", "showLogo", "showClassIcon", "showTitle", "showCog", "showResizeHandle", "futureFade",
            "arrowShape", "arrowColor", "arrowOpacity", "arrowSize", "arrowTextShown", "arrowTextSize", "customSizes",
            "titleSize", "activeSize", "listSize", "lineSpacing", "stepPadding", "footer", "dividers", "scrollbar", "stepLabel",
            "settingsButton" },
            { titleOutline = ENUM.outline, bodyOutline = ENUM.outline, footer = ENUM.footer, dividers = ENUM.dividers,
              scrollbar = ENUM.scrollbar, stepLabel = ENUM.stepLabel })
        local T = Sk and Sk.Timers
        Table(g, { "ui", "restedxpTimerLook" }, T and T.Look, LOOK, LOOK_ENUMS)
        Table(g, { "ui", "restedxpTimerText" }, T and T.Opt, { "skinTimers", "fillTexture", "fillColor", "fillColor2", "fillGradient",
            "fillOpacity", "labelFont", "labelOutline", "labelSize", "labelColor", "timeFont", "timeOutline", "timeSize",
            "timeColor", "barHeight", "textPadding", "showIcon" },
            { fillGradient = ENUM.gradient, labelOutline = ENUM.outline, timeOutline = ENUM.timeOutline })
    end

    g = Group("speakstone", "SpeakStone speech frame", { page = "speakstone", note = "Needs SpeakStone." })
    Switches(g, { "speakstoneSkin" })
    do
        local Sk = R.SpeakStoneSkin
        Table(g, { "ui", "speakstoneSkin" }, Sk and Sk.Look, LOOK, LOOK_ENUMS)
        Table(g, { "ui", "speakstoneSkinStyle" }, Sk and Sk.Style, { "nameFont", "nameSize", "nameColor", "textFont", "textSize",
            "textColor", "lineSpacing", "timeFont", "timeSize", "timeColor", "buttonFont", "buttonSize", "buttonText",
            "buttonFill", "buttonBorder", "accentColor", "showPortrait", "portraitSize", "portraitShape", "portraitBorderColor",
            "portraitBorderSize", "showProgress", "progressHeight", "progressColor", "trackColor", "rightClickClose", "padding" },
            { portraitShape = ENUM.shape })
    end

    local complete = true
    for _, grp in ipairs(groups) do if not grp.complete then complete = false end end
    return groups, complete
end

-- The groups, in the order the window lists them. { id, label, page, note, scope, fields, index, complete, custom, check }
function TC.Groups()
    if schema then return schema end
    local groups, complete = Define()
    if complete then schema = groups end
    return groups
end

function TC.Group(id)
    for _, g in ipairs(TC.Groups()) do if g.id == id then return g end end
end

-- Whether a group can be shared on this client right now (its feature and everything it needs are there).
local function Usable(g)
    if not g.complete then return false end
    if g.custom then return StatSets() ~= nil end
    return #g.fields > 0
end
TC.Usable = Usable

---------------------------------------------------------------------------
-- Reading what is set here
---------------------------------------------------------------------------
local function Container(f, create)
    local t = TwichUIDB
    for _, k in ipairs(f.at) do
        if type(t) ~= "table" then return nil end
        local nextT = t[k]
        if type(nextT) ~= "table" then
            if not create then return nil end
            nextT = {}
            t[k] = nextT
        end
        t = nextT
    end
    return t
end

local function Raw(f)
    local c = Container(f)
    if c then return c[f.key] end
end

-- What the feature is using: the saved value when it is usable, the default otherwise.
local function Effective(f)
    local v = Raw(f)
    if v ~= nil and KIND[f.kind](f, v) then return v end
    return f.default
end

local function Humanize(key)
    local s = key:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):lower()
    return (s:gsub("^%l", string.upper))
end
TC.Humanize = Humanize

local function Show(v)
    if v == true then return "on" elseif v == false then return "off" end
    return tostring(v)
end

---------------------------------------------------------------------------
-- What you include (kept in TwichUIDB.setup.twichui; Setups.lua checks its shape at load)
---------------------------------------------------------------------------
-- Reading the choice never writes anything: until you tick something, nothing of it is saved.
local function Peek()
    local db = ST.db
    local t = db and db.twichui
    if type(t) == "table" then return t end
end

local function Ensure()
    local db = ST.db
    if not db then return nil end
    if type(db.twichui) ~= "table" then db.twichui = { included = false, skip = {} } end
    if type(db.twichui.skip) ~= "table" then db.twichui.skip = {} end
    return db.twichui
end

function TC.Included()
    local t = Peek()
    return t ~= nil and t.included == true
end

-- Included, and at least one feature ticked that can be shared here.
function TC.WillInclude()
    if not TC.Included() then return false end
    for _, g in ipairs(TC.Groups()) do
        if TC.GroupSelected(g.id) and Usable(g) then return true end
    end
    return false
end

function TC.SetIncluded(on)
    local t = Ensure()
    if t then t.included = on and true or false end
end

function TC.GroupSelected(id)
    local t = Peek()
    return not (t and type(t.skip) == "table" and t.skip[id] == true)
end

function TC.SetGroupSelected(id, on)
    local t = Ensure()
    if t then t.skip[id] = (not on) and true or nil end
end

-- { { id, label, page, note, scope, count, selected, usable } } for the window.
function TC.GroupList()
    local list = {}
    for _, g in ipairs(TC.Groups()) do
        local count = g.custom and (Usable(g) and #((Weights.export() or { units = {} }).units) or 0) or #g.fields
        list[#list + 1] = { id = g.id, label = g.label, page = g.page, note = g.note, scope = g.scope, count = count,
            selected = TC.GroupSelected(g.id), usable = Usable(g), custom = g.custom ~= nil }
    end
    return list
end

---------------------------------------------------------------------------
-- Building what goes out
---------------------------------------------------------------------------
local function AddonVersion()
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, R.ADDON, "Version")
    if ok and type(v) == "string" then return v:sub(1, L.addon) end
end

-- The entry saved with your setup: effective values of the groups you included, as they are now. nil when
-- nothing is included. opts.all includes every usable group (a test); opts.selection overrides the saved choice.
function TC.Build(opts)
    opts = opts or {}
    local entry = { schema = TC.SCHEMA, status = "ok", made = time(), addon = AddonVersion(), groups = {} }
    local n, values = 0, 0
    for _, g in ipairs(TC.Groups()) do
        local want
        if opts.all then want = true
        elseif opts.selection then want = opts.selection[g.id] ~= false
        else want = TC.GroupSelected(g.id) end
        if want and Usable(g) then
            local data
            if g.custom then
                data = g.custom.export()
            else
                data = {}
                for _, f in ipairs(g.fields) do
                    data[f.slot] = data[f.slot] or {}
                    data[f.slot][f.key] = Effective(f)
                end
            end
            if data then
                entry.groups[g.id] = data
                n = n + 1
            end
        end
    end
    if n == 0 then return nil end
    return entry
end

-- For the offer: a few small numbers, nothing of the settings.
function TC.OfferInfo(entry)
    if type(entry) ~= "table" or entry.status ~= "ok" or type(entry.groups) ~= "table" then return nil end
    local n = 0
    for _ in pairs(entry.groups) do n = n + 1 end
    return { schema = entry.schema, groups = n }
end

---------------------------------------------------------------------------
-- Checking what arrives (or is read back): plain data, bounded, only named fields. Returns a table that shares
-- nothing with the input. Always returns a table for a non-nil input:
--   status "ok"       groups holds what passed; rejected[group] = how many values a group was dropped for
--   status "newer"    made by a TwichUI whose payload this one doesn't read: nothing is taken from it
--   status "damaged"  not a usable entry
---------------------------------------------------------------------------
-- Values under t, to a bounded depth (a deeper or looping table is counted as past the limit).
local function CountValues(t, depth)
    depth = depth or 1
    if depth > 6 then return L.values + 1 end
    local n = 0
    for _, v in pairs(t) do
        if type(v) == "table" then n = n + CountValues(v, depth + 1) else n = n + 1 end
        if n > L.values then return n end
    end
    return n
end

function TC.CleanEntry(raw)
    if raw == nil then return nil end
    if type(raw) ~= "table" then return { status = "damaged" } end
    local schemaNo = raw.schema
    if not Whole(schemaNo) or schemaNo < 1 then return { status = "damaged" } end
    if schemaNo > TC.SCHEMA then
        return { schema = schemaNo, status = "newer", addon = PlainText(raw.addon, L.addon) and raw.addon or nil }
    end
    if type(raw.groups) ~= "table" then return { schema = schemaNo, status = "damaged" } end
    local entry = {
        schema = schemaNo, status = "ok", groups = {}, unknown = 0, rejected = {},
        made = Finite(raw.made) and raw.made or nil,
        addon = PlainText(raw.addon, L.addon) and raw.addon or nil,
    }
    local total, examined = 0, 0
    local byId = {}
    for _, g in ipairs(TC.Groups()) do byId[g.id] = g end
    for id, data in pairs(raw.groups) do
        examined = examined + 1
        if examined > L.values then return { schema = schemaNo, status = "damaged", why = "too-large" } end
        local g = type(id) == "string" and byId[id]
        if not g or not Usable(g) then
            entry.unknown = entry.unknown + 1
        elseif type(data) ~= "table" then
            entry.rejected[g.id] = 1
        elseif g.custom then
            total = total + CountValues(data)
            if total > L.values then return { schema = schemaNo, status = "damaged", why = "too-large" } end
            local clean = g.custom.clean(data)
            if clean then entry.groups[g.id] = clean else entry.rejected[g.id] = 1 end
        else
            local out, bad = {}, 0
            for slot, vals in pairs(data) do
                examined = examined + 1
                if examined > L.values then return { schema = schemaNo, status = "damaged", why = "too-large" } end
                local idx = type(slot) == "string" and g.index[slot]
                if type(vals) ~= "table" then
                    bad = bad + 1
                elseif not idx then
                    entry.unknown = entry.unknown + 1
                else
                    for key, v in pairs(vals) do
                        total, examined = total + 1, examined + 1
                        if total > L.values or examined > L.values then return { schema = schemaNo, status = "damaged", why = "too-large" } end
                        local f = type(key) == "string" and idx[key]
                        if not f then
                            entry.unknown = entry.unknown + 1
                        elseif not KIND[f.kind](f, v) then
                            bad = bad + 1
                        else
                            out[slot] = out[slot] or {}
                            out[slot][key] = v
                        end
                    end
                end
            end
            if bad == 0 and g.check and not g.check(out) then bad = 1 end
            if bad > 0 then entry.rejected[g.id] = bad
            elseif next(out) ~= nil then entry.groups[g.id] = out end
        end
    end
    return entry
end

---------------------------------------------------------------------------
-- The review: everything that would change, before anything does
---------------------------------------------------------------------------
local function Profiles()
    local PF = R.Profiles
    if not PF then return nil end
    return PF
end

-- opts.selection = { [groupId] = false } leaves groups out.
-- Returns { ok, why, status, groups = { { id, label, scope, note, state, changes = { { label, old, new, reload } },
--   same, rejected } }, changed, reload = { labels }, absent = { labels }, profile, sharedWith, unknown, scopes }
function TC.Plan(entry, opts)
    opts = opts or {}
    local plan = { groups = {}, changed = 0, reload = {}, absent = {}, unknown = 0 }
    if type(entry) ~= "table" then plan.why = "There are no TwichUI settings in this setup." return plan end
    plan.status, plan.schema, plan.addon, plan.made = entry.status, entry.schema, entry.addon, entry.made
    if entry.status == "newer" then
        plan.why = "These TwichUI settings were made by a newer TwichUI than this one. Update TwichUI to read them; nothing was taken from them."
        return plan
    elseif entry.status ~= "ok" then
        plan.why = "These TwichUI settings arrived damaged and can't be used. Ask for the setup to be sent again."
        return plan
    end
    -- Checked again against this client's schema: a received copy was cleaned when it arrived, possibly by an
    -- earlier version of the schema.
    local clean = TC.CleanEntry(entry)
    if clean.status ~= "ok" then
        plan.status = clean.status
        plan.why = "These TwichUI settings arrived damaged and can't be used. Ask for the setup to be sent again."
        return plan
    end
    plan.unknown = (clean.unknown or 0) + (type(entry.unknown) == "number" and entry.unknown or 0)
    -- a group dropped when the setup arrived is still reported: it is not in the stored copy any more
    if type(entry.rejected) == "table" then
        for id, n in pairs(entry.rejected) do
            if type(id) == "string" and clean.rejected[id] == nil and type(n) == "number" then clean.rejected[id] = n end
        end
    end
    local PF = Profiles()
    plan.profile = PF and PF.Current() or nil
    plan.sharedWith = (PF and plan.profile) and #PF.UsedBy(plan.profile, true) or 0
    plan.profilesAvailable = PF and (PF.Available()) or false
    local W = R.Switches
    for _, g in ipairs(TC.Groups()) do
        local data = clean.groups[g.id]
        local rejected = clean.rejected[g.id]
        local row = { id = g.id, label = g.label, scope = g.scope, note = g.note, page = g.page, changes = {}, same = 0,
            selected = opts.selection == nil or opts.selection[g.id] ~= false }
        if rejected then
            row.state, row.rejected = "invalid", rejected
            plan.groups[#plan.groups + 1] = row
        elseif data then
            if not Usable(g) then
                row.state = "unavailable"
            elseif g.custom then
                local changes = g.custom.plan(data)
                for _, c in ipairs(changes) do
                    row.changes[#row.changes + 1] = { label = ("%s, tree %d"):format(Humanize(c.class:lower()), c.line), old = "your values", new = c.what,
                        scope = "account" }
                end
                row.same = #data.units - #changes
                row.state = #changes > 0 and "changed" or "same"
            else
                for _, f in ipairs(g.fields) do
                    local v = data[f.slot] and data[f.slot][f.key]
                    if v ~= nil then
                        local cur = Effective(f)
                        if cur ~= v then
                            local reload = f.switch and W and W.NeedsReload(f.key) or false
                            row.changes[#row.changes + 1] = { label = Humanize(f.key), key = f.key, slot = f.slot, old = Show(cur), new = Show(v),
                                reload = reload, scope = f.scope }
                            if reload and row.selected then plan.reload[#plan.reload + 1] = Humanize(f.key) end
                        else
                            row.same = row.same + 1
                        end
                    end
                end
                row.state = #row.changes > 0 and "changed" or "same"
            end
            plan.groups[#plan.groups + 1] = row
            if row.selected then plan.changed = plan.changed + #row.changes end
        elseif Usable(g) then
            plan.absent[#plan.absent + 1] = g.label
        end
    end
    plan.ok = #plan.groups > 0
    if not plan.ok then plan.why = "This setup holds no TwichUI settings this version can use." end
    plan.entry = clean
    return plan
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------
local FAILURE = {
    combat = "That has to wait until you're out of combat.",
    nothing = "There is nothing to change: your settings already match.",
    none = "There are no TwichUI settings in this setup.",
}

function TC.Explain(code, extra)
    if FAILURE[code] then return FAILURE[code] end
    if code == "profiles" and R.Profiles then return R.Profiles.Explain(extra) end
    return "That couldn't be done."
end

local function TakenProfile(name)
    local low = name:lower()
    for _, other in ipairs(R.Profiles.List()) do
        if other:lower() == low then return true end
    end
    return false
end

-- A free profile name for an import from `who`.
function TC.NewProfileName(who)
    local P = R.Persist
    local base = ("From " .. tostring(who or "a friend")):gsub("[%c|]", ""):gsub("%s+", " ")
    if P.ProfileName(base) == nil then base = "Shared settings" end
    return P.FreeProfileName(base, TakenProfile) or P.FreeProfileName("Shared settings", TakenProfile)
end

-- entry: a cleaned entry (pack.twichui). opts: selection, from (a name, for the Undo copy and the profile name),
-- newProfile (true: a copy of the profile in use is made and used first).
-- Returns true, report | false, reason code, extra.
--   report = { changed, groups = { label }, reload = { label }, reloadPending, failed = { part }, profile, newProfile, scopes }
function TC.Apply(entry, opts)
    opts = opts or {}
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    local PF = R.Profiles
    local available, why = PF.Available()
    if not available then return false, "profiles", why end
    local plan = TC.Plan(entry, opts)
    if not plan.ok then return false, "none" end
    if plan.changed == 0 then return false, "nothing" end

    local newName
    if opts.newProfile then
        newName = TC.NewProfileName(opts.from)
        if not newName then return false, "profiles", "taken" end
        local ok, code = PF.Duplicate(newName)
        if not ok then return false, "profiles", code end
    end

    local data = plan.entry.groups
    local undo = { created = time(), from = type(opts.from) == "string" and opts.from:sub(1, 64) or nil,
        profile = PF.Current(), fields = {}, weights = {} }
    local writes, groups = {}, {}
    local weightPlans = {}
    for _, row in ipairs(plan.groups) do
        if row.selected and row.state == "changed" then
            groups[#groups + 1] = row.label
            local g = TC.Group(row.id)
            if g.custom then
                weightPlans[#weightPlans + 1] = { g = g, plan = g.custom.plan(data[row.id]), data = data[row.id] }
            else
                for _, f in ipairs(g.fields) do
                    local v = data[row.id][f.slot] and data[row.id][f.slot][f.key]
                    if v ~= nil and Effective(f) ~= v then
                        writes[#writes + 1] = { f = f, value = v }
                        local raw = Raw(f)
                        undo.fields[#undo.fields + 1] = { g = g.id, s = f.slot, k = f.key, had = raw ~= nil, v = Copy(raw) }
                    end
                end
            end
        end
    end

    -- Plain assignments only. Everything above has been checked, so nothing here is expected to fail; if it
    -- does, what was written is put back.
    local ok, err = pcall(function()
        for _, w in ipairs(writes) do Container(w.f, true)[w.f.key] = w.value end
        for _, wp in ipairs(weightPlans) do
            local records = wp.g.custom.apply(wp.data, wp.plan)
            for _, r in ipairs(records) do undo.weights[#undo.weights + 1] = r end
        end
    end)
    if not ok then
        R.Fault("applying TwichUI settings", err)
        for i = #undo.fields, 1, -1 do
            local u = undo.fields[i]
            local g = TC.Group(u.g)
            local f = g and g.index[u.s] and g.index[u.s][u.k]
            if f then
                local c = Container(f, true)
                if c then c[f.key] = u.had and u.v or nil end
            end
        end
        Weights.restore(undo.weights)
        return false, "failed"
    end

    undo.count = #undo.fields + #undo.weights
    if ST.db then ST.db.twichUndo = undo end

    local refreshOk, _, info = PF.Refresh("import")
    local report = {
        changed = plan.changed, groups = groups, reload = plan.reload,
        reloadPending = refreshOk and info and info.reload or false,
        failed = refreshOk and info and info.failed or {}, profile = PF.Current(), newProfile = newName,
        from = opts.from,
    }
    TC.last = report
    return true, report
end

---------------------------------------------------------------------------
-- Undo: the values the last import replaced, put back
---------------------------------------------------------------------------
-- Shape check of an Undo copy (our own data, but a hand-edited file is possible).
local function CleanUndo(u)
    if type(u) ~= "table" or type(u.profile) ~= "string" or type(u.fields) ~= "table" or type(u.weights) ~= "table" then return false end
    return true
end
TC.CleanUndo = CleanUndo

function TC.Undo()
    local snap = ST.db and ST.db.twichUndo
    if not CleanUndo(snap) then return false, "none" end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    local PF = R.Profiles
    local available, why = PF.Available()
    if not available then return false, "profiles", why end
    if PF.Current() ~= snap.profile then return false, "profile", snap.profile end
    local n = 0
    for i = #snap.fields, 1, -1 do
        local u = snap.fields[i]
        local g = type(u) == "table" and type(u.g) == "string" and TC.Group(u.g)
        local f = g and g.index[u.s] and g.index[u.s][u.k]
        if f then
            local c = Container(f, true)
            if c then
                if u.had then c[f.key] = u.v else c[f.key] = nil end
                n = n + 1
            end
        end
    end
    n = n + Weights.restore(snap.weights)
    ST.db.twichUndo = nil
    local ok, _, info = PF.Refresh("import-undo")
    return true, { restored = n, reloadPending = ok and info and info.reload or false }
end

-- Whether there is an Undo copy, and what it would put back: { count, profile, from, created } or nil.
function TC.UndoInfo()
    local snap = ST.db and ST.db.twichUndo
    if not CleanUndo(snap) then return nil end
    local PF = R.Profiles
    return { count = (type(snap.count) == "number" and snap.count) or (#snap.fields + #snap.weights), profile = snap.profile,
        from = snap.from, created = snap.created, here = PF and PF.Current() == snap.profile }
end

-- For the Saved data window.
function TC.StorageItem()
    local snap = ST.db and ST.db.twichUndo
    if not CleanUndo(snap) then return nil end
    return {
        key = "twichui-undo", kind = "Undo copy",
        label = "Undo for imported TwichUI settings",
        detail = ("%d settings, replaced %s"):format(#snap.fields + #snap.weights, date("%b %d", type(snap.created) == "number" and snap.created or 0)),
        bytes = ST.SizeOf(snap), remove = function() ST.db.twichUndo = nil end,
        warn = "Without it, the last import of TwichUI settings can't be undone.",
    }
end

---------------------------------------------------------------------------
-- Words for the window
---------------------------------------------------------------------------
-- Size, for the offer and the "about" figures.
function TC.Bytes(entry)
    if type(entry) ~= "table" or type(entry.groups) ~= "table" then return 0 end
    return ST.SizeOf(entry.groups)
end
