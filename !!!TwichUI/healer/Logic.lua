-- TwichUI: Healer Watch, the decisions (pure)
-- Everything here takes plain tables and returns plain values: no game call, no frame, no saved data, no clock of its
-- own. The live panel (Watch.lua), the settings window's preview and the simulations call the same functions, so what
-- a scenario shows is what the panel would show.
--
-- Three observations are kept apart and never stand in for one another:
--   mana   measured: { state = "ok" | "secret" | "none" | "unknown", cur, max, pct }. "secret": the game shows the
--          value but keeps it from addons (it can be drawn, not compared); "none": the unit reports no mana pool;
--          "unknown": nothing usable was read. Only "ok" has a percentage, and only "ok" can be low.
--   drink  confirmed by an aura: { state = "yes" | "no" | "hidden" | "unknown", evidence }. "hidden": the game keeps
--          auras from addons right now (combat, an encounter), which is not "not drinking".
--   chat   reported by the healer: { phrase, mode, excerpt, channel, at } or nil. "drinking" said in chat is a message,
--          never confirmed drinking; "oom" is a message, never a mana reading.
-- And the selection: { guid, name, unit, source = "manual" | "auto", problem = nil | "noRole" | "ambiguous" | "away" }.

local R = TwichUI
local HL = {}
R.HealerLogic = HL

---------------------------------------------------------------------------
-- Mana bands, with recovery margins. t: HW.NormalizeThresholds(...). A band begins strictly below its threshold and
-- ends at or above its clear point; between the two the previous band holds, so a healer hovering at 30% doesn't make
-- the panel flicker. pct nil (no measured mana) gives nil: no band, and never "low".
---------------------------------------------------------------------------
function HL.NextBand(prev, pct, t)
    if type(pct) ~= "number" then return nil end
    if prev == "critical" and pct < t.criticalClear then return "critical" end
    if pct < t.critical then return "critical" end
    if (prev == "low" or prev == "critical") and pct < t.lowClear then return "low" end
    if pct < t.low then return "low" end
    return "ok"
end

---------------------------------------------------------------------------
-- Chat phrases. A message and a phrase are compared as literal text (string.find with plain = true, never a pattern),
-- lowercased (ASCII letters; other letters are compared as they are), with runs of spaces made one.
--   word:  the phrase appears with no letter or digit directly before or after it ("oom" in "oom!" or "going oom", not
--          in "boom" or "ooms"). Bytes of non-ASCII letters count as letters, so a phrase never matches inside a word
--          in another alphabet.
--   exact: the whole message is the phrase, apart from spaces and ASCII punctuation at either end ("oom!" = "oom").
-- Neither understands meaning: "not oom" matches "oom" as whole words. That is what the settings say.
---------------------------------------------------------------------------
function HL.Normalize(text)
    if type(text) ~= "string" then return "" end
    return (text:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function StripEnds(s) return (s:gsub("^[%p%s]+", ""):gsub("[%p%s]+$", "")) end

local function WordByte(b) return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95) end

function HL.MatchPhrase(norm, phrase)
    local p = phrase and phrase.text
    if type(p) ~= "string" or p == "" then return false end
    if phrase.mode == "exact" then return StripEnds(norm) == StripEnds(p) end
    local from = 1
    while true do
        local s, e = norm:find(p, from, true)
        if not s then return false end
        if not WordByte(norm:byte(s - 1)) and not WordByte(norm:byte(e + 1)) then return true end
        from = s + 1
    end
end

-- The first phrase (in list order) a message matches: index, phrase; nil when none.
function HL.Match(text, phrases)
    local norm = HL.Normalize(text)
    if norm == "" then return nil end
    for i, p in ipairs(phrases or {}) do
        if HL.MatchPhrase(norm, p) then return i, p end
    end
    return nil
end

-- What was said, made safe to draw: chat markup (colors, links, textures, atlases, Battle.net names) removed, any "|"
-- left over and control characters dropped, spaces collapsed, and at most max characters (whole characters) with "...".
function HL.Excerpt(text, max)
    if type(text) ~= "string" then return "" end
    max = max or 40
    local s = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
        :gsub("|A.-|a", ""):gsub("|K.-|k", ""):gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local n, cut = 0, nil
    for pos in s:gmatch("()[^\128-\191]") do
        n = n + 1
        if n > max then cut = pos break end
    end
    if cut then s = s:sub(1, cut - 1):gsub(" $", "") .. "..." end
    return s
end

---------------------------------------------------------------------------
-- Who to watch. candidates: the group as read now, each { guid, name, unit, role, isPlayer } (role "HEALER", "TANK",
-- "DAMAGER", or nil when none is assigned or it can't be read). choice: nil (automatic) or { guid, name } (the
-- player's own choice). Never decided from class, spells or gear.
--   manual: the chosen guid, wherever it now is in the group; if it isn't there, nobody else is watched in its place.
--   auto:   the one member with the Healer role; none or several means the player has to choose.
---------------------------------------------------------------------------
function HL.Resolve(candidates, choice)
    if choice and choice.guid then
        for _, c in ipairs(candidates) do
            if c.guid == choice.guid then
                return { guid = c.guid, name = c.name, unit = c.unit, source = "manual", isPlayer = c.isPlayer }
            end
        end
        return { guid = choice.guid, name = choice.name, source = "manual", problem = "away" }
    end
    local found, count = nil, 0
    for _, c in ipairs(candidates) do
        if c.role == "HEALER" then
            count = count + 1
            found = found or c
        end
    end
    if count == 1 then
        return { guid = found.guid, name = found.name, unit = found.unit, source = "auto", isPlayer = found.isPlayer }
    end
    return { source = "auto", problem = count == 0 and "noRole" or "ambiguous", count = count }
end

HL.PROBLEM = {
    noRole = "Choose a healer",
    ambiguous = "Choose a healer",
    away = "%s isn't in your group",
}
HL.PROBLEM_DETAIL = {
    noRole = "No one in your group has the Healer role, so there is no one to watch until you choose.",
    ambiguous = "More than one member has the Healer role, so you choose which one to watch.",
    away = "The healer you chose isn't in your group now. Nobody else is watched in their place; choose again, or go back to automatic.",
}

---------------------------------------------------------------------------
-- What the panel shows, from a selection and its observations. cfg: a table with the settings Present reads (Watch.lua
-- and the previews pass the same one). Returns a new table:
--   name, manaText (nil: no number), manaSecret (the number and bar come from the game's restricted values: draw them
--   from unit), unit, barValue (0..100, nil: none), barTone ("ok" | "low" | "critical" | "unknown"), drinking,
--   drinkHidden, chat, chatText, status (one line: every state that is true, most important first), statusTone, items.
---------------------------------------------------------------------------
local function ManaText(mana, format)
    if format == "none" then return nil end
    local pct = mana.pct and math.floor(mana.pct) .. "%" or nil
    local amounts = (mana.cur and mana.max) and (math.floor(mana.cur) .. " / " .. math.floor(mana.max)) or nil
    if format == "current" then return amounts or pct end
    if format == "both" and pct and amounts then return pct .. "  " .. amounts end
    return pct
end

local function Ago(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return seconds .. "s ago" end
    return math.floor(seconds / 60) .. "m ago"
end

-- A chat signal is current until `at + expiry`.
function HL.ChatActive(chat, now, expiry)
    return chat ~= nil and type(chat.at) == "number" and type(now) == "number" and now >= chat.at and now - chat.at < expiry
end

function HL.Present(sel, obs, cfg, now)
    local v = { name = sel and sel.name or nil, unit = sel and sel.unit or nil, items = {} }
    local items = v.items
    local problem = sel and sel.problem
    if not sel or problem then
        items[#items + 1] = problem == "away" and HL.PROBLEM.away:format(sel.name or "Your healer") or HL.PROBLEM.noRole
        v.statusTone = "warn"
        v.problem = problem or "noRole"
        v.barTone, v.status = "unknown", items[1]
        return v
    end
    obs = obs or {}
    local mana = obs.mana or { state = "unknown" }
    local life = obs.life
    local gone = life == "offline" or life == "dead"
    if life == "offline" then items[#items + 1] = "Offline"
    elseif life == "dead" then items[#items + 1] = "Dead" end

    -- mana: a stale or unreadable value is never shown as current
    if not gone and mana.state == "ok" then
        v.manaText = ManaText(mana, cfg.manaFormat)
        v.barValue = math.max(0, math.min(100, mana.pct))
        v.barTone = obs.band or "ok"
    elseif not gone and mana.state == "secret" then
        v.manaSecret = cfg.manaFormat ~= "none"
        v.barTone = "ok"
        v.barValue = nil
        v.secretBar = true
    else
        v.manaText = cfg.manaFormat ~= "none" and "--" or nil
        v.barTone = "unknown"
    end

    local drink = obs.drink or { state = "unknown" }
    if not gone and drink.state == "yes" then
        v.drinking = true
        items[#items + 1] = "Drinking"
    end
    v.drinkHidden = not gone and (drink.state == "hidden" or drink.state == "unknown")

    if cfg.chatDisplay ~= "off" and HL.ChatActive(obs.chat, now, cfg.chatExpiry) then
        v.chat = true
        local c = obs.chat
        local said = cfg.chatDisplay == "text" and ("Said \226\128\156" .. (c.excerpt ~= "" and c.excerpt or c.phrase) .. "\226\128\157") or "Mana message"
        if cfg.showElapsed then said = said .. " " .. Ago(now - c.at) end
        v.chatText = said
        items[#items + 1] = said
    end

    if not gone and cfg.showManaState then
        if obs.band == "critical" then items[#items + 1] = "Critical mana"
        elseif obs.band == "low" then items[#items + 1] = "Low mana" end
    end
    if not gone and (mana.state == "none" or mana.state == "unknown") then items[#items + 1] = "Mana not readable" end

    v.status = table.concat(items, " \194\183 ")
    v.statusTone = gone and "warn" or ((obs.band == "critical" or obs.band == "low") and obs.band or "dim")
    return v
end

---------------------------------------------------------------------------
-- When the panel shows. Scope and availability are gates, not alerts; attention conditions are combined with Any.
--   input = { enabled, scopeActive, inCombat, sel, obs, now }, cfg: the settings.
-- Returns shown, reason (a short code, for the diagnostics and the settings window).
---------------------------------------------------------------------------
function HL.Attention(obs, cfg, now)
    local hit = {}
    if not obs then return hit end
    local gone = obs.life == "offline" or obs.life == "dead"
    if not gone and obs.mana and obs.mana.state == "ok" then   -- unknown or restricted mana is never "low"
        if cfg.attnCritical and obs.band == "critical" then hit.critical = true end
        if cfg.attnLow and (obs.band == "low" or obs.band == "critical") then hit.low = true end
    end
    if cfg.attnDrinking and not gone and obs.drink and obs.drink.state == "yes" then hit.drinking = true end
    if cfg.attnChat and cfg.chatDisplay ~= "off" and HL.ChatActive(obs.chat, now, cfg.chatExpiry) then hit.chat = true end
    return hit
end

local ATTENTION_ORDER = { "critical", "low", "drinking", "chat" }

function HL.Visible(input, cfg)
    if not input.enabled then return false, "off" end
    if not input.scopeActive then return false, "scope" end
    if input.inCombat and not cfg.showInCombat then return false, "combat" end
    if not input.inCombat and not cfg.showOutOfCombat then return false, "outOfCombat" end
    local sel = input.sel
    if not sel or sel.problem then
        if cfg.showSetup then return true, "setup" end
        return false, "noHealer"
    end
    if cfg.visibility == "always" then return true, "always" end
    local hit = HL.Attention(input.obs, cfg, input.now)
    for _, k in ipairs(ATTENTION_ORDER) do
        if hit[k] then return true, "attention:" .. k end
    end
    return false, "calm"
end

HL.REASONS = {
    off = "Healer Watch is off.",
    scope = "You're not where it applies.",
    combat = "Hidden in combat by your choice.",
    outOfCombat = "Hidden out of combat by your choice.",
    noHealer = "No healer to watch, and the setup message is hidden during play.",
    setup = "Shown to ask you to choose a healer.",
    always = "Shown: it shows whenever it applies.",
    calm = "Hidden: none of the attention conditions you chose is true.",
    ["attention:critical"] = "Shown: critical mana.",
    ["attention:low"] = "Shown: low mana.",
    ["attention:drinking"] = "Shown: confirmed drinking.",
    ["attention:chat"] = "Shown: a recent mana message.",
    preview = "Showing the preview.",
}

---------------------------------------------------------------------------
-- Simulations: made-up selections and observations for the settings window. Each call builds new tables, so a
-- scenario never shares anything with the live panel.
---------------------------------------------------------------------------
HL.SCENARIOS = {
    { "normal", "Normal mana" }, { "low", "Low mana" }, { "critical", "Critical mana" }, { "drinking", "Drinking" },
    { "chat", "Recent \"oom\" message" }, { "drinkChat", "Drinking and chat" }, { "offline", "Healer offline" },
    { "dead", "Healer dead" }, { "noMana", "Mana unavailable" }, { "drinkHidden", "Drinking can't be seen" },
    { "noHealer", "No healer selected" },
}
local SAMPLE_NAME = "Elyndra"

function HL.Scenario(key, now)
    local sel = { guid = "Sample", name = SAMPLE_NAME, unit = nil, source = "auto" }
    local function Mana(pct) return { state = "ok", cur = math.floor(4200 * pct / 100), max = 4200, pct = pct } end
    local obs = { life = "alive", mana = Mana(78), band = "ok", drink = { state = "no" } }
    if key == "low" then obs.mana, obs.band = Mana(26), "low"
    elseif key == "critical" then obs.mana, obs.band = Mana(9), "critical"
    elseif key == "drinking" then obs.mana, obs.band, obs.drink = Mana(41), "ok", { state = "yes", evidence = "sample" }
    elseif key == "chat" then obs.mana, obs.band = Mana(22), "low"; obs.chat = { phrase = "oom", excerpt = "oom", at = now - 3 }
    elseif key == "drinkChat" then
        obs.mana, obs.band, obs.drink = Mana(34), "ok", { state = "yes", evidence = "sample" }
        obs.chat = { phrase = "oom", excerpt = "oom, drinking", at = now - 2 }
    elseif key == "offline" then obs.life = "offline"
    elseif key == "dead" then obs.life = "dead"
    elseif key == "noMana" then obs.mana, obs.band = { state = "unknown" }, nil
    elseif key == "drinkHidden" then obs.mana, obs.band, obs.drink = Mana(57), "ok", { state = "hidden" }
    elseif key == "noHealer" then sel, obs = { source = "auto", problem = "noRole" }, nil end
    return sel, obs
end
