-- Settings presentation only. Stable page/row IDs, setters, defaults and full help belong to Kit/the feature.
-- The reference editor keeps its finished custom controls. Other pages share the same art and materials.
local R = TwichUI
local K, W, M = R.SettingsKit, R.SettingsWidgets, R.SettingsMaterial
local D = { pages = {} }
R.SettingsDesign = D

local function Page(key, intro, secondary)
    D.pages[key] = { intro = intro, secondary = secondary or {} }
end
Page("overview", "Make yourself at home.", { "Interface layout", "General" })
Page("notifications", "Choose the moments you want to hear about.", { "Notification previews" })
Page("notificationsLook", "Preview a card, then make it your own.", { "Divider", "Accent and backdrop", "Reset" })
Page("reminders", "Your reminders, your way.")
Page("ammoCustom", "Teach reminders which ammunition your character can use.")
Page("healerWatch", "Keep your healer's mana and messages in view.", { "Mana thresholds", "Chat channels and sound", "Colors", "Mana bar", "Attention effects", "Position" })
Page("buffBack", "Choose which friendly buffs you want to return.")
Page("qol", "Small conveniences. Choose what works for you.")
Page("markers", "Mark targets and places with your own shortcuts.")
Page("markersTarget", "Choose your target sequence and keys.", { "Target marker keys" })
Page("markersWorld", "Choose your world marker sequence and keys.", { "World marker keys" })
Page("markersBar", "Put your markers within easy reach.", { "Size and look" })
Page("chatClean", "Keep the conversations you want to read.", { "Built-in filters", "Live view and test" })
Page("chatCleanChannels", "Choose which channels your filters cover.")
Page("chatCleanRules", "Build filters and try them before using them.")
Page("chatCleanLive", "See what was filtered and test a message.")
Page("food", "Keep food and water ready to use.", { "Appearance" })
Page("camping", "Your camp essentials in one place.", { "Appearance" })
Page("campingRest", "Watch your Sleeping Bag rest progress.", { "Notches", "Border", "Text", "When it ends" })
Page("hazard", "Choose sounds for the auras you want to notice.", { "Volume", "Built-in rules", "Reset" })
Page("hazardRules", "Choose an aura, an event and an alert sound.")
Page("restock", "Choose what to keep stocked at merchants.", { "Question window appearance" })
Page("restockItems", "Set a target quantity for each item you keep stocked.")
Page("magicInventory", "Choose where your items belong, then review the moves.")
Page("auction", "Keep selling and collecting mail close at hand.")
Page("workshop", "Plan your crafts and see the materials you still need.", { "What it does", "Shopping", "Opportunities" })
Page("chronicle", "Keep a journal of your adventures.")
Page("chronicleLook", "Make your journal comfortable to read.", { "Border", "Controls and accents" })
Page("cozyBag", "Follow your progress toward the Cozy Sleeping Bag.", { "Previews" })
Page("pins", "Save places and share a destination with your group.", { "Data bar", "Sound", "Appearance" })
Page("pings", "Point out a place to your group.")
Page("pinsLook", "Choose how your pins, labels and windows look.", { "Data bar menu appearance", "New pin window appearance" })
Page("mapToolbar", "Keep your map tools and filters together.")
Page("worldMap", "Make the world map easier to explore.", { "Detail" })
Page("worldMapPlaces", "Choose the places shown on your map.")
Page("navigation", "Choose how you follow a route.", { "Getting there", "Arriving and leaving the route" })
Page("navigationLook", "Preview your route display while you adjust it.", { "Frame theme", "Frame background and border" })
Page("npcs", "Remember the vendors and trainers you discover.", { "How they show" })
Page("npcsList", "Manage and share your discovered services.", { "Checking what the game reports", "Remove" })
Page("npcsKnowledge", "Browse known services and find one on the map.")
Page("guildLocations", "Choose whether guildmates can see your location.")
Page("gear", "Choose where you see estimated gear upgrades.")
Page("statWeights", "Choose a talent tree for your class, then a priority or numeric weights.")
Page("mage", "Keep travel, conjuring and refreshments ready.", { "Broker menu appearance", "Refreshments panel appearance" })
Page("refreshmentShares", "Plan the refreshments you want to share with your group.")
Page("classBars", "Choose your resources and when to show them.", { "Reset" })
Page("classBarsLayout", "Arrange your resource bars.", { "Reset" })
Page("classBarsLook", "Choose the shared look, then customize individual resources.", { "Background and border", "Reset" })
Page("classBarsEffects", "Choose the moments your resource bars emphasize.", { "Reset" })
Page("barGlows", "Make the action buttons you care about stand out.")
Page("barGlowsSpells", "Choose spells and customize their glow.")
Page("skins", "Make supported addons feel at home with TwichUI.")
Page("speakstone", "Make dialogue comfortable to read.", { "Playback text", "Controls", "Portrait", "Progress line" })
Page("restedxp", "Choose your guide's behavior and appearance.", { "Window background and border", "Current step", "Header and footer", "Text size", "Spacing", "Scroll bar", "Waypoint arrow", "Timer bars", "Timer bar background and border" })
Page("targetArt", "Choose dragon artwork for your target frame.", { "Fine-tune each artwork", "Reset" })
Page("sharing", "Share selected configurations and review incoming changes.")
Page("profiles", "Choose the settings this character uses.", { "Delete or reset" })
Page("troubleshooting", "Check status, then open the tools you need.", { "Temporary tracing" })

function D.IsReference()
    local UI = R.SettingsUI
    local key = UI and UI.Selected and UI.Selected()
    local page = key and K.pages[key]
    return page and page.def.designReference == true
end
function D.Intro(page)
    return D.pages[page.key] and D.pages[page.key].intro or page.def.description or ""
end
function D.Secondary(page, label)
    for _, name in ipairs(D.pages[page.key] and D.pages[page.key].secondary or {}) do
        if name == label then return true end
    end
    return false
end

-- Long forms expose one player task at a time. The original rows, dependencies and setters stay authoritative.
-- Small forms and already focused card/list editors intentionally have no task strip.
local TASKS = {
    notifications = { { "Arrivals", "Zone arrival" }, { "Training", "New training" }, { "Friends", "Friend login" }, { "Party", "Party deaths" },
        { "Comfort", "Accessibility" }, { "Try it", "Notification previews", "Appearance" } },
    notificationsLook = { { "Customize", "Notification appearance", "Text" },
        { "Frame", "Divider", "Accent and backdrop" }, { "Try and reset", "Preview", "Reset" } },
    healerWatch = { { "Watch", "Who to watch", "When to show" }, { "Readings", "What to show", "Mana thresholds", "Drinking and messages", "Chat channels and sound" },
        { "Appearance", "Appearance and testing", "Colors", "Mana bar", "Attention effects", "Position" }, { "Try it" } },
    chronicle = { { "Record", "Automatic entries" }, { "Window", "Appearance" } },
    chronicleLook = { { "Text", "The Chronicle window", "Typography" },
        { "Surfaces", "Background", "Border" }, { "Details", "Controls and accents" } },
    navigation = { { "Follow a route", "Navigation", "How to start", "What it shows" },
        { "Travel options", "Getting there" }, { "Arrival", "Arriving and leaving the route" } },
    navigationLook = { { "Display", "Preview", "Frame and arrow", "Text" },
        { "Trail", "The trail" }, { "Surfaces", "Frame theme", "Frame background and border" } },
    camping = { { "On the bar", "Camping bar", "What is on the bar", "Eat button" },
        { "Visibility", "When it shows" }, { "Appearance", "Appearance" } },
    campingRest = { { "Progress", "Sleeping bag bar", "The bar", "When it ends" },
        { "Appearance", "Notches", "Border", "Text" } },
    hazard = { { "Sounds", "Hazard alerts", "Alert categories", "Volume" },
        { "Built-ins", "Built-in rules", "Reset" } },
    mage = { { "Travel", "Mage Travel" }, { "Conjure", "Mage Conjuring", "Mage refreshments" },
        { "Selling", "Sell ordinary food and drink" }, { "Appearance", "Broker menu appearance", "Refreshments panel appearance" } },
    pins = { { "Share a place", "Party pins", "Waypoint commands", "Placing and showing" },
        { "Controls", "Data bar", "Sound", "Appearance" } },
    pings = { { "Share a ping", "Map pings" }, { "Marker and sound", "Marker and sound" },
        { "Recent pings", "Recent pings" }, { "Try it", "Try and reset" } },
    pinsLook = { { "Map labels", "Map text" }, { "Windows", "Window appearance", "New pin window appearance" },
        { "Data bar", "Data bar menu appearance" } },
    npcsList = { { "Your list", "Your list", "Sharing" }, { "Inspect and remove", "Checking what the game reports", "Remove" } },
    classBars = { { "Display", "Class resource bars", "When to show" }, { "Placement", "Place and preview", "Reset" } },
    classBarsLook = { { "Bars", "Fill" }, { "Labels", "Text" }, { "Surfaces", "Background and border", "Reset" } },
    restedxp = { { "Setup", "RestedXP guide window" },
        { "Guide behavior", "Map waypoint", "Show and hide automatically", "EllesmereUI quest tracker" },
        { "Reading", "Text", "Current step", "Text size", "Spacing" },
        { "Surfaces", "Window background and border", "Header and footer", "Scroll bar" },
        { "Arrow / timers", "Waypoint arrow", "Timer bars", "Timer bar background and border" } },
    speakstone = { { "Reading", "SpeakStone speech frame", "Text" }, { "Frame", "Frame", "Portrait", "Progress line" }, { "Advanced", "Playback text", "Controls" } },
    targetArt = { { "Choose artwork", "Target dragon artwork", "Artwork for each kind of enemy", "Preview" },
        { "Appearance", "Appearance", "Fine-tune each artwork", "Reset" } },
    troubleshooting = { { "Status", "Status", "Optional integrations" },
        { "Tools", "Performance and support", "Layout setup", "Full report", "Temporary tracing" } },
}
D.tasks = TASKS
function D.Tasks(page)
    if page.reviewedTasks ~= nil then return page.reviewedTasks or nil end
    local groups = TASKS[page.key]
    if not groups then page.reviewedTasks = false; return nil end
    local headers, available = {}, {}
    for _, row in ipairs(page.rows) do if row.kind == "header" then headers[row:GetName()] = true end end
    for _, group in ipairs(groups) do
        local present = page.key == "healerWatch" and group[1] == "Try it"
        for i = 2, #group do if headers[group[i]] then present = true end end
        if present then available[#available + 1] = group end
    end
    -- An absent optional integration must not offer empty task buttons.
    page.reviewedTasks = #available > 1 and available or false
    return page.reviewedTasks or nil
end
function D.TaskFor(page, label)
    local groups = TASKS[page.key]
    if not groups then return nil end
    for _, group in ipairs(groups) do
        for i = 2, #group do if group[i] == label then return group[1] end end
    end
    return groups[1][1]
end
function D.HostTask(page)
    if page.key == "healerWatch" then return "Try it" end
    return D.TaskFor(page, page.def.hostAfter)
end
function D.Summary(text)
    return type(text) == "string" and (text:match("^(.-[.!?])%s") or text) or ""
end
local SUMMARIES = {
    speakstone = { ["SpeakStone speech frame"] = "Style the speech frame. Narration, timing and position stay with SpeakStone.",
        ["Text"] = "Set the speaker and dialogue text for comfortable reading." },
    restedxp = { ["RestedXP guide window"] = "Style the guide window. Guide content and progress stay with RestedXP." },
    guildLocations = { ["Your location"] = "Sharing sends your current position to guildmates running TwichUI. Invisible receives without sending; Off does neither. No location history." },
    mage = { ["Sell ordinary food and drink"] = "Optional merchant selling or EllesmereUI junk marking. Dry run reports only; turn it off to act. Special, conjured and protected items stay in your bags." },
    profiles = { ["Profiles"] = "Characters using the same profile share changes. Duplicate it for an independent setup.",
        ["Make a profile"] = "New starts from defaults. Duplicate copies your current profile. Both switch this character to the new profile." },
    sharing = { ["Addon configurations"] = "Choose what to share or apply in the sharing window. Review incoming changes before applying; Undo restores your previous settings." },
    restock = { ["Vendor restocking"] = "Choose items and target quantities. Merchant purchases follow your existing restocking mode and spending limit.",
        ["Question window appearance"] = "Style the purchase question. Items and prices still need your confirmation in that window." },
    hazard = { ["Hazard alerts"] = "Sounds for listed auras affecting you. TwichUI cannot identify damage sources or avoidable hits on this client.",
        ["Alert categories"] = "Choose each category's sound and channel. Categories describe urgency, not damage." },
    npcsList = { ["Sharing"] = "Share discovered NPCs with your group, guild or a named player. Live finds and whole lists have separate choices.",
        ["Remove"] = "Removal cannot be undone. An NPC is remembered again when you deal with it." },
    workshop = { ["What's it worth?"] = "Design the item tooltip using preview data. Disenchant values are unavailable; auction values are shown before fees." },
}
function D.SectionSummary(page, header, text)
    local summaries = SUMMARIES[page.key]
    return summaries and summaries[header:GetName()] or D.Summary(text)
end

-- Wrappers are settings-local. Core Look and all live gameplay surfaces retain their APIs and appearance.
local Text, Button, EditBox, Checkbox, Panel, Dropdown, Slider = W.Text, W.Button, W.EditBox, W.Checkbox, W.Panel, W.Dropdown, W.Slider
local Well, Scroll, Card, Tab = W.Well, W.Scroll, W.Card, W.Tab
function W.Text(parent, kind, layer)
    local text = Text(parent, kind, layer)
    if not D.IsReference() then
        local size = ({ brand = 25, title = 25, heading = 17, body = 14, small = 13, meta = 12 })[kind] or 14
        M.ReminderFont(text, size, kind == "body" or kind == "title")
    end
    return text
end
function W.Button(parent, label, width, kind, callback)
    local button = Button(parent, label, width, kind, callback)
    if not D.IsReference() then
        M.ReminderControl(button, kind == "danger" and "danger" or kind == "primary" and "confirmation" or "action")
        button.twichSharedDefault = true
    end
    return button
end
function W.EditBox(parent, width, height)
    local field = EditBox(parent, width, height)
    if not D.IsReference() then M.ReminderControl(field, "field") end
    return field
end
function W.Checkbox(parent, callback)
    if D.IsReference() then return Checkbox(parent, callback) end
    return M.Pill(parent, callback, true)
end
function W.Panel(frame)
    local lines = Panel(frame)
    if D.IsReference() then return lines end
    for _, line in pairs(lines or {}) do line:Hide() end
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    -- A section has exactly the material used by Reminders' Appearance/When/Sound cards.
    local face = M.PanelFace(frame, "walnut")
    frame.twichSettingsPanel = face
    local parts = {}
    for _, part in ipairs(face.parts) do parts[#parts + 1] = part end
    for _, part in ipairs(face.rim.parts) do parts[#parts + 1] = part end
    return parts
end
function W.Dropdown(parent, width, callback, compact)
    local control = Dropdown(parent, width, callback, compact)
    if not D.IsReference() then M.ReminderControl(control, compact and "action" or "dropdown") end
    return control
end
function W.Slider(parent, width, callback, material)
    return Slider(parent, width, callback, material or not D.IsReference())
end
function W.Tab(parent, label, width, callback)
    if D.IsReference() then return Tab(parent, label, width, callback) end
    return M.Segment(parent, label, width, callback)
end
function W.Well(frame, alpha)
    if D.IsReference() then return Well(frame, alpha) end
    local lines = Well(frame, alpha)
    for _, line in pairs(lines or {}) do line:Hide() end
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    local face = M.PanelFace(frame, "canvas")
    local parts = {}
    for _, part in ipairs(face.parts) do parts[#parts + 1] = part end
    for _, part in ipairs(face.rim.parts) do parts[#parts + 1] = part end
    return parts
end
function W.Scroll(parent, width)
    local scroll, content = Scroll(parent, width)
    if not D.IsReference() then
        local fit = M.ScrollRail(scroll)
        if fit then
            content:HookScript("OnSizeChanged", function() fit(content:GetHeight()) end)
            fit(content:GetHeight())
        end
    end
    return scroll, content
end
function W.Card(parent, left, top, right, bottom)
    if D.IsReference() then return Card(parent, left, top, right, bottom) end
    -- Draw directly on the host: an extra child frame would cover the host's own icons and labels.
    return R.SettingsCraft.Sheet(parent, "field", { layer = "BACKGROUND", sub = 0,
        bounds = { left, top, right, bottom } })
end
