-- TwichUI Settings: search across every page
-- Reads the pages' descriptions (Kit.lua), never their frames: searching builds no page. The index is made once,
-- the first time something is searched for, and holds each page, section and setting with the words that find
-- it: its label, its page and section, a few other words players use for it, and its tooltip (a match only in
-- the tooltip ranks below the rest). The query is plain text: no patterns, nothing evaluated.

local R = TwichUI
local K = R.SettingsKit
local Search = {}
R.SettingsSearch = Search

Search.LIMIT = 60
Search.SEP = "  \194\183  "   -- a middle dot between a page and its section

-- Other words for things, by row id (a setting's name) or page key.
local ALIASES = {
    arrival = "zone text banner title",
    arrivalReducedMotion = "animation motion",
    friendLogin = "battle.net bnet toast popup online",
    friendLoginChime = "sound volume",
    pinsSound = "volume chime",
    mapPings = "ping pings alert world map group party raid",
    pinsPingGesture = "ctrl alt click shortcut key modifier",
    pinsPingSound = "volume chime",
    pinsPingReduced = "animation motion accessibility",
    pinsWayAlso = "tomtom waypointui /way",
    pinsMinimap = "minimap",
    foodDrinkUnlock = "move position anchor /unlock",
    navigationUnlockMode = "move position anchor /unlock ellesmere mover",
    qolQuickKeybind = "keybind bindings hotkey game menu escape",
    qolSummons = "summon portal warlock meeting stone auto accept teleport",
    qolSummonsFrom = "trust who friends guild group strangers",
    qolSummonsWait = "delay how long countdown",
    qolResurrect = "res rez revive auto accept",
    qolResurrectCombat = "battle res brez combat rez",
    qolReleasePvP = "auto release spirit ghost graveyard bg pvp",
    qolReleaseWait = "delay how long",
    qolDuels = "block refuse auto decline duel spam",
    qolDuelsFrom = "exceptions allow friends guild",
    qolDuelsToDeath = "lethal death duel",
    mageTravel = "teleport portal",
    mageConjure = "water bread conjure",
    mageSell = "vendor merchant junk",
    mageSellMode = "junk ellesmere bags mark sell marker",
    quietLogin = "chat spam login messages",
    media = "fonts sounds libsharedmedia lsm",
    chronicleClock = "24-hour 12-hour time clock",
    gearBagStyle = "icon marker",
    shareTransport = "whisper direct transport",
    restedxpArrowShape = "arrow pointer",
    welcomeBack = "login bookmark",
}

local function Plain(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower())
end

local function Clean(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s%s+.*$", ""))
end

-- A result's one line about what it is: a feature card's own sentence for the card and the settings in it, else
-- the first sentence of the row's description. nil when there is none.
local function FirstSentence(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n.*$", "")
    return text:match("^(.-[%.!?])%s") or text
end
local function Describe(row, tip)
    local card = row.card and row or row.primaryOf or row.ruleOf
    if card then return card.card.what end
    return FirstSentence(tip)
end

local index

-- Builds the index (once). Only ever called after the pages are described.
function Search.Build()
    if index then return index end
    index = {}
    local groupLabel = {}
    for _, group in ipairs(K.GROUPS) do groupLabel[group.key] = group.label end
    local order = 0
    local function Add(entry)
        order = order + 1
        entry.order = order
        entry.labelLow = Plain(entry.label)
        entry.hay = Plain(table.concat({ entry.label, entry.context or "", entry.words or "" }, " "))
        index[#index + 1] = entry
    end
    for _, page in ipairs(K.NavOrder()) do
        local def = page.def
        local parent = page.parent and K.pages[page.parent]
        Add({
            kind = "page", page = page.key, label = page.name, desc = FirstSentence(def.description),
            context = parent and parent.name or groupLabel[page.group] or "TwichUI",
            words = table.concat({ page.nav or "", def.keywords or "", def.description or "", ALIASES[page.key] or "" }, " "),
        })
        for _, row in ipairs(page.rows) do
            -- a card whose switch has the card's own name is found through the switch (one result, not two)
            local duplicate = row.card and row.primary and Clean(row.primary:GetName()) == Clean(row:GetName())
            if row.kind ~= "link" and not duplicate then
                local label = Clean(row:GetName())
                if label ~= "" then
                    local section = row.section and Clean(row.section:GetName()) or nil
                    -- a page under another is a tab of it: "Mage . Refreshment shares . Section"
                    local context = parent and (parent.name .. Search.SEP .. K.TabLabel(page)) or page.name
                    if row.kind ~= "header" and section and section ~= "" and section:lower() ~= page.name:lower() then
                        context = context .. Search.SEP .. section
                    end
                    local ok, tip = pcall(row.GetTooltip, row)
                    Add({
                        kind = row.kind == "header" and "section" or "setting", page = page.key, row = row,
                        label = label, context = context, words = ALIASES[row.id] or "",
                        tip = ok and Plain(tip) or "", desc = Describe(row, ok and tip or nil),
                    })
                end
            end
        end
    end
    return index
end

-- Forgets the index (the pages were described again; only tests do that).
function Search.Reset() index = nil end

-- Whether the index has been made this session (for /tui diagnostics).
function Search.Built() return index ~= nil end

local function Words(query)
    local list = {}
    for word in query:lower():gmatch("%S+") do list[#list + 1] = word end
    return list
end

local function AllIn(words, text)
    for _, w in ipairs(words) do
        if not text:find(w, 1, true) then return false end
    end
    return true
end

-- Every word in one text or the other. The same as AllIn on the two joined (a word has no spaces, so it can't
-- span the join), without making that joined text for every entry at every keystroke.
local function AllInEither(words, text, more)
    for _, w in ipairs(words) do
        if not (text:find(w, 1, true) or more:find(w, 1, true)) then return false end
    end
    return true
end

-- Returns { { entry, score, tipOnly }, ... } best first, at most Search.LIMIT, for a query of plain text.
function Search.Run(query)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return {} end
    local words = Words(query)
    local low = query:lower()
    local wordStart = "%f[%w]" .. words[1]:gsub("%p", "%%%0")   -- the first word at the start of a word
    local results = {}
    for _, e in ipairs(Search.Build()) do
        local score
        if e.labelLow == low then score = 120
        elseif e.labelLow:find(low, 1, true) == 1 then score = 100   -- starts with it
        elseif AllIn(words, e.labelLow) then
            score = 80
            if e.labelLow:find(wordStart) then score = 85 end
        elseif AllIn(words, e.hay) then score = 50
        elseif e.tip and AllInEither(words, e.hay, e.tip) then score = 10 end
        if score then
            if e.kind == "page" then score = score + 5 elseif e.kind == "section" then score = score + 2 end
            results[#results + 1] = { entry = e, score = score, tipOnly = score < 20 }
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.entry.order < b.entry.order
    end)
    for i = #results, Search.LIMIT + 1, -1 do results[i] = nil end
    return results
end

-- A short note for a result that can't be used as it is: greyed out, or not shown with the current
-- choices. Read when the results are drawn, so it is current.
function Search.Note(entry)
    local row = entry.row
    if not row then return nil end
    if row.kind ~= "header" and not row:Enabled() then return row:DisabledReason() end
    if row.kind ~= "header" and not row:Shown() then return "Shown only with some of the choices above it." end
    return nil
end
