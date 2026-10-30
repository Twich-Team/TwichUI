-- TwichUI settings: Healer Watch (healer/). Four cards (Who to watch, What to show, When to show, Appearance and
-- testing) whose rows call healer/Config.lua's Get/Set and the watcher's own functions, then a frame of this window's
-- own: the inline preview with its scenarios and the on-screen preview, the chat phrases and their tester, and live
-- diagnostics. Built the first time the page is shown; rows are made once and reused on every redraw. The scenario and
-- whether diagnostics are open last for the session only. Nothing here is needed for Healer Watch to work, and nothing
-- here sends a message, reads chat history or changes who is watched except when you choose.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.HealerWatchPage = P

local W = 644                 -- the settings window's content width
local PAD, GAP = 14, 12
local PREVIEW_H = 128
local DOT = "  \194\183  "

local f, built
local height = 560
local queued, relayoutQueued = false, false
local phraseRows = {}
local diagOpen = false
local said, saidTone

local function Wg() return R.SettingsWidgets end
local function HW() return R.HealerWatch end
local function Watch() return R.HealerWatcher end
local function On() return R:Enabled("healerWatch") end

local function Tone(fs, tone)
    local G = Wg()
    local pal = G.pal
    G.Color(fs, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or (tone == "quiet" and pal.stone or pal.textDim)))
end

local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

local function SourceWords(s)
    if s.problem == "away" then return "your choice, not in the group now" end
    if s.problem then return nil end
    return s.source == "manual" and "your choice for this session" or "the one with the Healer role"
end

-- "Elyndra (the one with the Healer role)", or why nobody is watched.
local function WatchingText()
    local s = Watch().Selection()
    if s.problem == "away" then return (s.name or "Your healer") .. " isn't in your group", "warn" end
    if s.problem == "ambiguous" then return "Choose a healer: more than one has the Healer role", "warn" end
    if s.problem then return "Choose a healer: no one has the Healer role", "warn" end
    return ("%s (%s)"):format(s.name or "?", SourceWords(s)), "ok"
end

local function ScopeLabel()
    for _, c in ipairs(HW().CHOICES.scope) do if c[1] == HW().Get("scope") then return c[2] end end
    return ""
end

---------------------------------------------------------------------------
-- The hosted frame: redrawing
---------------------------------------------------------------------------
function P.QueueRefresh(delay)
    if queued then return end
    queued = true
    C_Timer.After(delay or 0, function()
        queued = false
        P.Refresh()
    end)
end

local function QueueRelayout()
    if relayoutQueued then return end
    relayoutQueued = true
    C_Timer.After(0, function()
        relayoutQueued = false
        local UI = R.SettingsUI
        if UI and UI.Refresh then UI.Refresh() end
    end)
end

function P.Height() return height end
function P.Parts() return { frame = f, phraseRows = phraseRows } end

local function Say(text, tone)
    said, saidTone = text, tone
    P.QueueRefresh()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function ScenarioChoices()
    local out = {}
    for i, s in ipairs(R.HealerLogic.SCENARIOS) do out[i] = { value = s[1], label = s[2] } end
    return out
end

local function ModeLabel(mode)
    for _, m in ipairs(HW().PHRASE_MODES) do if m[1] == mode then return m[2] end end
    return mode
end

local function PhraseRow(i)
    if phraseRows[i] then return phraseRows[i] end
    local G = Wg()
    local row = CreateFrame("Frame", nil, f.phrases)
    row:SetSize(W - PAD * 2, 24)
    row.text = G.Text(row, "body")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetWidth(300)
    row.text:SetWordWrap(false)
    row.mode = G.Button(row, "Whole words", 130, "secondary", function()
        local list = HW().Phrases()
        local p = row.index and list[row.index]
        if not p then return end
        local ok, why = HW().SetPhraseMode(row.index, p.mode == "word" and "exact" or "word")
        if not ok then Say(why, "warn") end
    end)
    row.mode:SetPoint("LEFT", 320, 0)
    R.Interact.Tip(row.mode, "How it matches", function()
        return HW().PHRASE_MODES[1][3] .. "\n\n" .. HW().PHRASE_MODES[2][3] .. "\n\nClick to switch."
    end)
    row.remove = G.Button(row, "Remove", 80, "danger", function()
        if not row.index then return end
        local list = HW().Phrases()
        local p = list[row.index]
        local ok, why = HW().RemovePhrase(row.index)
        if ok and p then Say(("Removed \"%s\"."):format(p.text), "ok") elseif not ok then Say(why, "warn") end
    end)
    row.remove:SetPoint("RIGHT", -4, 0)
    R.Interact.Tip(row.remove, "Remove", "Takes this phrase out of the list. Nothing else changes.")
    phraseRows[i] = row
    return row
end

local function Panel(title)
    local G = Wg()
    local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
    p:SetWidth(W)
    G.Panel(p)
    p.title = G.Text(p, "heading")
    p.title:SetPoint("TOPLEFT", PAD, -12)
    p.title:SetText(title)
    return p
end

local function Build()
    built = true
    local G = Wg()
    local I = R.Interact

    -- Preview: a scenario drawn with your settings, inline and (optionally) on screen
    f.preview = Panel("Preview and scenarios")
    f.previewNote = G.Text(f.preview, "small")
    f.previewNote:SetWidth(W - PAD * 2)
    f.previewNote:SetWordWrap(true)
    f.previewNote:SetText("A sample drawn with your settings and made-up readings. It reads nothing from your group, sends nothing and changes nothing; the live panel carries on underneath.")
    f.scenarioLabel = G.Text(f.preview, "body")
    f.scenarioLabel:SetText("Scenario")
    f.scenario = G.Dropdown(f.preview, 220, function(value)
        Watch().SetScenario(value)
        P.QueueRefresh()
    end)
    f.scenario:SetChoices(ScenarioChoices)
    I.Tip(f.scenario, "Scenario", "What the sample shows: normal, low or critical mana, drinking, a recent \"oom\", both at once, an offline or dead healer, mana or drinking that can't be read, or no healer chosen. Used by the sample here and by Show on screen.")
    f.stage = CreateFrame("Frame", nil, f.preview, "BackdropTemplate")
    f.stage:SetSize(W - PAD * 2, PREVIEW_H)
    G.Surface(f.stage, G.pal.well, 0.75, G.pal.bronzeLo, 0.45)
    G.Recess(f.stage, 0.8)
    local tag = G.Tag(f.stage, "SAMPLE")
    tag:SetPoint("TOPRIGHT", -6, -6)
    f.surface = R.HealerDisplay.NewSurface(f.stage)
    f.surface:SetPoint("CENTER", f.stage, "CENTER", 0, 0)
    f.show = G.Button(f.preview, "Show on screen", 140, "secondary", function()
        local Wt = Watch()
        if Wt.PreviewActive() then Wt.PreviewStop()
        else
            local ok, why = Wt.PreviewStart(false)
            if not ok then Say(why == "off" and "Turn Healer Watch on first: the on-screen preview uses the real panel." or "The preview waits until you are out of combat.", "warn") end
        end
        P.QueueRefresh()
    end)
    I.Tip(f.show, "Show on screen", "Shows the chosen scenario in the real panel, where it sits and at its size, marked \"Preview\". It ends when you close these settings, enter combat or turn Healer Watch off. The live panel is hidden while it shows, never drawn twice.")
    f.move = G.Button(f.preview, "Move it", 110, "secondary", function()
        local Wt = Watch()
        if Wt.PositioningActive() then Wt.PositionEnd()
        else
            local ok, why = Wt.PreviewStart(true)
            if not ok then Say(why == "off" and "Turn Healer Watch on first." or "It can be moved when you are out of combat.", "warn") end
        end
        P.QueueRefresh()
    end)
    f.flashTry = G.Button(f.preview, "Try the flash", 120, "secondary", function()
        local ok, why = Watch().TestFlash("chat")
        if not ok then Say(why == "preview" and "Show the preview on screen first, then try the flash." or "Nothing flashed: Reduced motion is on in Notifications.", "warn") end
    end)
    I.Tip(f.flashTry, "Try the flash", "Plays the attention flash once in the on-screen preview, whether or not the flashes are switched on, so you can judge it. It never plays with Notifications' Reduced motion.")
    I.Tip(f.move, "Move it", "Shows the preview with a highlighted handle. Drag the handle to move the panel; right-click it, or press Lock, when you are done. The panel never takes clicks otherwise.")

    -- Chat phrases and the tester
    f.phrases = Panel("Chat phrases")
    f.phrasesNote = G.Text(f.phrases, "small")
    f.phrasesNote:SetWidth(W - PAD * 2)
    f.phrasesNote:SetWordWrap(true)
    f.phrasesNote:SetText("Words that count as a mana message from the watched healer. They are literal text, not patterns, and nothing reads their meaning: \"not oom\" still matches \"oom\". A message only counts when the game says it came from the healer you watch; names are never matched. A phrase like \"drinking\" is shown as something they said, never as confirmed drinking.")
    f.addBox = G.EditBox(f.phrases, 260, 22)
    f.addBox:SetMaxLetters(HW().PHRASE_MAX * 4)
    local addMode = "word"
    f.addMode = G.Button(f.phrases, ModeLabel(addMode), 130, "secondary", function()
        addMode = addMode == "word" and "exact" or "word"
        f.addMode.text:SetText(ModeLabel(addMode))
    end)
    I.Tip(f.addMode, "How it matches", HW().PHRASE_MODES[1][3] .. "\n\n" .. HW().PHRASE_MODES[2][3])
    local function Add()
        local ok, why = HW().AddPhrase(f.addBox:GetText(), addMode)
        if ok then f.addBox:SetText(""); Say("Added.", "ok") else Say(why, "warn") end
    end
    f.addBox:SetScript("OnEnterPressed", function(self) Add(); self:ClearFocus() end)
    I.Tip(f.addBox, "New phrase", ("Up to %d characters. Letters are compared without case; spaces and punctuation at either end of a whole-message phrase are ignored."):format(HW().PHRASE_MAX))
    f.add = G.Button(f.phrases, "Add", 70, "secondary", Add)
    f.broad = G.Button(f.phrases, "Add \"mana\" (broad)", 150, "secondary", function()
        local b = HW().BROAD_PHRASE
        local ok, why = HW().AddPhrase(b.text, b.mode)
        Say(ok and "Added \"mana\". It also matches \"mana potion\" and other passing mentions." or why, ok and "ok" or "warn")
    end)
    I.Tip(f.broad, "Add \"mana\"", "A broad keyword: any message with the word \"mana\" counts, including passing mentions such as \"mana potion\" or \"no mana issues\". Off unless you add it.")
    f.resetPhrases = G.Button(f.phrases, "Reset phrases", 120, "danger", function()
        R.Interact.Confirm("TWICHUI_HEALER_PHRASES_RESET", "Put the chat phrases back to the default three (\"oom\", \"out of mana\", \"need mana\")?\n\nOnly the phrase list changes.", function()
            HW().ResetPhrases()
            Say("Phrases reset.", "ok")
        end, { accept = "Reset" })
    end)
    I.Tip(f.resetPhrases, "Reset phrases", "Puts the list back to \"oom\", \"out of mana\" and \"need mana\", after asking. Nothing else changes.")
    f.testLabel = G.Text(f.phrases, "body")
    f.testLabel:SetText("Try a message")
    f.testBox = G.EditBox(f.phrases, 300, 22)
    f.testBox:SetMaxLetters(255)
    f.testBox:SetScript("OnTextChanged", function() P.QueueRefresh(0.15) end)
    I.Tip(f.testBox, "Try a message", "Type what a healer might say to see which phrase, if any, it matches. It is never sent to chat and never shown in the panel.")
    f.testResult = G.Text(f.phrases, "small")
    f.testResult:SetWidth(W - PAD * 2 - 330)
    f.testResult:SetWordWrap(true)
    f.say = G.Text(f.phrases, "small")
    f.say:SetWidth(W - PAD * 2)

    -- Live diagnostics
    f.diag = Panel("Live diagnostics")
    f.diagToggle = G.Button(f.diag, "Show", 90, "secondary", function()
        diagOpen = not diagOpen
        P.QueueRefresh()
    end)
    I.Tip(f.diagToggle, "Live diagnostics", "What Healer Watch knows right now: who it watches and how it chose them, the game unit it reads, each reading and whether it can be trusted, the drinking evidence, the chat signal and why the panel is shown or hidden. Only for you; nothing here is saved or sent.")
    f.diagText = G.Text(f.diag, "small")
    f.diagText:SetWidth(W - PAD * 2)
    f.diagText:SetWordWrap(true)
    f.diagText:SetJustifyH("LEFT")
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function LayoutPreview(y)
    local p, Wt = f.preview, Watch()
    local h = 36
    Put(f.previewNote, p, PAD, h)
    h = h + (f.previewNote:GetStringHeight() or 24) + 10
    Put(f.scenarioLabel, p, PAD, h + 4)
    local key = Wt.Scenario()
    local label = key
    for _, s in ipairs(R.HealerLogic.SCENARIOS) do if s[1] == key then label = s[2] end end
    f.scenario:SetValue(key, label)
    Put(f.scenario, p, PAD + 70, h)
    f.show.text:SetText(Wt.PreviewActive() and not Wt.PositioningActive() and "Hide" or "Show on screen")
    f.move.text:SetText(Wt.PositioningActive() and "Lock" or "Move it")
    Put(f.show, p, W - PAD - 110 - 8 - 140, h)
    Put(f.move, p, W - PAD - 110, h)
    h = h + 32
    Put(f.flashTry, p, PAD, h)
    h = h + 32
    Put(f.stage, p, PAD, h)
    R.HealerDisplay.DrawSurface(f.surface, Wt.ScenarioView(key), Wt.Config(), W - PAD * 2 - 20, PREVIEW_H - 20)
    h = h + PREVIEW_H + 12
    p:SetHeight(h)
    Put(p, f, 0, y)
    return h
end

local function LayoutPhrases(y)
    local p = f.phrases
    local h = 36
    Put(f.phrasesNote, p, PAD, h)
    h = h + (f.phrasesNote:GetStringHeight() or 36) + 10
    local list = HW().Phrases()
    for i, ph in ipairs(list) do
        local row = PhraseRow(i)
        row.index = i
        row.text:SetText(ph.text)
        row.mode.text:SetText(ModeLabel(ph.mode))
        Put(row, p, PAD, h)
        h = h + 26
    end
    for i = #list + 1, #phraseRows do
        phraseRows[i].index = nil
        phraseRows[i]:Hide()
    end
    if #list == 0 then
        f.say:SetText("No phrases: chat is listened to but nothing will match. Add one, or reset to the defaults.")
        Tone(f.say, "warn")
    end
    h = h + 6
    Put(f.addBox, p, PAD, h)
    Put(f.addMode, p, PAD + 268, h)
    Put(f.add, p, PAD + 406, h)
    Put(f.broad, p, W - PAD - 150, h)
    h = h + 30
    Put(f.resetPhrases, p, PAD, h)
    h = h + 34
    Put(f.testLabel, p, PAD, h + 4)
    Put(f.testBox, p, PAD + 100, h)
    local text = f.testBox:GetText() or ""
    if text == "" then
        f.testResult:SetText("Type a message to see what it matches.")
        Tone(f.testResult, "quiet")
    else
        local i, ph = Watch().TestPhrase(text)
        if i then
            f.testResult:SetText(("Matches \"%s\" (%s). It would show as: Said \226\128\156%s\226\128\157"):format(ph.text, ModeLabel(ph.mode):lower(), R.HealerLogic.Excerpt(text, 40)))
            Tone(f.testResult, "ok")
        else
            f.testResult:SetText("No phrase matches, so it wouldn't count.")
            Tone(f.testResult, "quiet")
        end
    end
    Put(f.testResult, p, PAD + 410, h + 2)
    h = h + math.max(28, (f.testResult:GetStringHeight() or 12) + 10)
    if said or #list == 0 then
        if said then f.say:SetText(said); Tone(f.say, saidTone) end
        Put(f.say, p, PAD, h)
        h = h + (f.say:GetStringHeight() or 12) + 8
    else
        f.say:Hide()
    end
    h = h + 4
    p:SetHeight(h)
    Put(p, f, 0, y)
    return h
end

local function Flag(v) if v == nil then return "unknown" end return v and "yes" or "no" end
local SECRECY = { [0] = "never restricted", [1] = "always restricted", [2] = "restricted at times" }

local function DiagLines()
    local s = Watch().Snapshot()
    local L = {}
    local function Line(fmt, ...) L[#L + 1] = fmt:format(...) end
    Line("Switch: %s. Where it applies: %s (here: %s). In combat: %s.", s.enabled and "on" or "off", tostring(s.scope), Flag(s.scopeActive), Flag(s.inCombat))
    if s.problem then
        Line("Selection: none (%s, %s).", tostring(s.source), s.problem)
    elseif s.guid then
        Line("Selection: %s, %s. Game unit: %s. Identity: %s.", tostring(s.name), s.source == "manual" and "your choice" or "Healer role", tostring(s.unit), tostring(s.guid))
    else
        Line("Selection: not read yet (it is read where Healer Watch applies, while it is on).")
    end
    local mana = s.mana == "ok" and ("%d%% (%d / %d), valid"):format(math.floor(s.manaPct or 0), s.manaCur or 0, s.manaMax or 0)
        or (s.mana == "secret" and "restricted by the game: drawn, not judged (no low or critical)")
        or (s.mana == "none" and "no mana pool reported") or "not read"
    Line("Mana: %s. Band: %s. Life: %s.", mana, tostring(s.band or "none"), tostring(s.life or "unknown"))
    local drink = s.drink == "yes" and ("confirmed (" .. (s.drinkEvidence == "name" and ("aura named \"" .. tostring(s.drinkName) .. "\"") or tostring(s.drinkEvidence)) .. ")")
        or (s.drink == "no" and "no drinking aura seen") or (s.drink == "hidden" and "can't be seen right now (the game hides auras)") or "not looked at yet"
    Line("Drinking: %s.", drink)
    Line("Chat: %s. Group chat hidden from addons here: %s.", s.chatPhrase and ("\"%s\", %ds left"):format(s.chatPhrase, math.ceil(s.chatLeft or 0)) or "no current message", Flag(s.chatLockdown))
    Line("Messages seen %d, matched %d, from others %d, unreadable %d, repeats %d.", s.chatSeen, s.chatMatched, s.chatOther, s.chatSecret, s.chatDuplicates)
    Line("Auras hidden from addons now: %s. Mana restriction: %s.", Flag(s.aurasSecret), SECRECY[s.manaSecrecy] or "not reported")
    Line("Panel: %s. %s", s.shown and "shown" or "hidden", R.HealerLogic.REASONS[s.reason] or tostring(s.reason))
    return table.concat(L, "\n")
end

local function LayoutDiag(y)
    local p = f.diag
    local h = 36
    f.diagToggle.text:SetText(diagOpen and "Hide" or "Show")
    Put(f.diagToggle, p, W - PAD - 90, 8)
    if diagOpen then
        f.diagText:SetText(DiagLines())
        Put(f.diagText, p, PAD, h)
        h = h + (f.diagText:GetStringHeight() or 60) + 10
    else
        f.diagText:Hide()
    end
    p:SetHeight(h)
    Put(p, f, 0, y)
    return h
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local y = 0
    y = y + LayoutPreview(y) + GAP
    y = y + LayoutPhrases(y) + GAP
    y = y + LayoutDiag(y)
    local h = math.max(1, y)
    f:SetHeight(h)
    if h ~= height then
        height = h
        QueueRelayout()
    end
end

-- "Preview particles": one burst in the chosen color and strength on the sample surface here and, while the on-screen
-- preview is showing, on that panel too (the preview's own state; never the live panel). Returns whether one played.
function P.PlayParticles()
    if not (f and built and f.surface) then return false, "page" end
    local D = R.HealerDisplay
    local cfg = { particleColor = HW().Get("particleColor"), particleIntensity = HW().Get("particleIntensity") }
    local ok, why = D.PreviewParticles(f.surface, cfg)
    if ok and Watch().PreviewActive() and D.Frame() and D.Frame():IsShown() then D.PreviewParticles(D.Frame(), cfg) end
    return ok, why
end

function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:SetWidth(W)
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build() end
        P.Refresh()
    end)
    f:SetScript("OnHide", function()
        if f.addBox then f.addBox:ClearFocus() end
        if f.testBox then f.testBox:ClearFocus() end
        if f.surface then R.HealerDisplay.StopSurfaceEffects(f.surface) end
        said = nil
    end)
    return f
end

-- Registered once (this file is loaded once a session): a change anywhere redraws the frame and the status rows, but
-- only while the page is shown.
if R.HealerWatch then R.HealerWatch.Subscribe(function() P.QueueRefresh() end) end
if R.HealerWatcher then
    R.HealerWatcher.OnChange(function()
        if f and f:IsShown() then
            P.QueueRefresh(0.1)
            K.RefreshOverview()
        end
    end)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
K.Page({
    key = "healerWatch", icon = "healerWatch", name = "Healer Watch", order = 24, group = "everyday",
    description = "One healer's mana, whether they are drinking, and what they just said about mana, in a small panel. Off until you turn it on.",
    keywords = "healer heal healing mana oom out of mana drink drinking water regen regeneration party dungeon group role pull wait chat message phrase low critical bar preview scenario diagnostics",
    overview = {
        label = "Healer Watch", tip = "One healer's mana, confirmed drinking and recent mana messages in a small panel, in dungeons.",
        when = function() return R.HealerWatch ~= nil end,
        status = function() return K.OnOff(R:Enabled("healerWatch")) end,
    },
    when = function() return R.HealerWatch ~= nil and R.HealerWatcher ~= nil and R.HealerDisplay ~= nil end,
    build = function()
        local MS = R.MenuStyle
        local hw, Wt = HW(), Watch()
        local Under = K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local resettable = {}
        local function Setting(key, varType, label, set)
            local name = "healerWatch" .. key:sub(1, 1):upper() .. key:sub(2)
            local s = K.Proxy(name, varType, label, hw.DEFAULTS[key], function() return hw.Get(key) end, set or function(v) hw.Set(key, v) end)
            -- the place has a reset of its own (Reset position); this page's Reset keeps it, so it isn't listed there
            if s and key ~= "point" and key ~= "x" and key ~= "y" then resettable[#resettable + 1] = { setting = s, default = hw.DEFAULTS[key] } end
            return s
        end
        local main
        local function Check(key, label, tip, isOn, why)
            return Under(K.Checkbox(Setting(key, BOOL, label, function(v) hw.Set(key, v and true or false) end), tip), main, isOn or On, why)
        end
        local function Pick(key, label, tip, choices, isOn, why, set)
            return Under(K.Dropdown(Setting(key, STRING, label, set), choices or function() return hw.CHOICES[key] end, tip), main, isOn or On, why)
        end
        local function Range(key, label, tip, isOn, why)
            local lim = hw.LIMITS[key]
            return Under(K.Slider(Setting(key, NUMBER, label, function(v) hw.Set(key, math.floor(v + 0.5)) end), lim[1], lim[2], tip), main, isOn or On, why)
        end
        local function Swatch(key, label, tip) return Under(K.Swatch(Setting(key, STRING, label), tip), main, On) end
        local function Label(key)
            for _, c in ipairs(hw.CHOICES[key] or {}) do if c[1] == hw.Get(key) then return c[2] end end
            return tostring(hw.Get(key))
        end

        -- 1. Who to watch
        K.Card({
            title = "Who to watch", icon = "healerWatch",
            what = "A small panel with one healer's mana, whether they are drinking, and what they just said about mana, so you can judge for yourself when to wait.",
            summary = function()
                if not On() then return "Off." end
                local text = WatchingText()
                return text .. DOT .. ScopeLabel()
            end,
            consequence = "It only informs. It never sends a message, never says whether to pull and never acts for you. Your choice of healer lasts for this session and group; nothing about who heals is saved.",
            inline = true,
            details = {
                { "How is the healer found?", "If you chose someone, it watches them. Otherwise it watches the one member of your group whose role is set to Healer (in the group finder, a role check or the unit menu). If no one, or more than one, has that role, it asks you to choose. It never guesses from class, spells or gear." },
                { "What if they leave or swap places?", "It follows the player, not the party slot: reordering never moves what it saw to someone else. If the player you chose leaves, it says so and watches nobody else in their place until you choose again or go back to automatic. Leaving the group ends your choice." },
                { "What can't it see?", "The game can hide auras from addons in combat and during encounters, so drinking is then shown as \"can't be seen\", never as not drinking. It documents group chat as hidden from addons inside dungeons and raids, in which case mana messages can't be read there at all. It can restrict mana values too: then the bar and number still show, but low and critical can't be worked out. The live diagnostics below say which applies right now." },
            },
        })
        main = K.Toggle("healerWatch", "Show Healer Watch",
            "On: the panel shows where it applies (five-player dungeons unless you choose otherwise), for the healer chosen below. Off: no panel, and nothing is listened for. It reads only that one player's mana, life and auras and what they say in the channels you choose; it never sends anything.")
        K.Status("Watching",
            function() return (WatchingText()) end,
            function()
                local s = Wt.Selection()
                if s.problem then return R.HealerLogic.PROBLEM_DETAIL[s.problem] end
                return s.live and "Read from your group now." or "Read from your group when the page was drawn."
            end,
            "Who Healer Watch watches and how it chose them. Read when this page is drawn; it is not polled.",
            function() local _, tone = WatchingText(); return tone end)
        Under(K.Choice("healerWatchHealer", "Healer to watch",
            "Automatic watches the one group member with the Healer role. Choosing a member watches them for this session and group, whatever their role; you are listed too. Nothing is saved: after a reload, or when you leave the group, it is automatic again.",
            STRING, "auto", function() return (Wt.Choice()) end,
            function(value)
                local ok, why = Wt.Choose(value)
                if not ok then R.Print("%s", why) end
            end,
            function()
                local list = {}
                for k, entry in ipairs(Wt.PickerChoices()) do list[k] = entry end
                return list
            end), main, On)
        K.Status("Right now",
            function()
                if not On() then return "Off" end
                if not Wt.ScopeActive() then return "Not where it applies" end
                local s = Wt.Snapshot()
                return s.shown and "Shown" or "Hidden"
            end,
            function()
                if not On() then return nil end
                local s = Wt.Snapshot()
                if not Wt.ScopeActive() then return "It applies in: " .. ScopeLabel() .. "." end
                return R.HealerLogic.REASONS[s.reason]
            end,
            "Whether it applies where you are, and whether the panel is shown and why. Read when this page is drawn.",
            function() return (On() and Wt.ScopeActive()) and "ok" or "quiet" end)

        -- 2. What to show
        K.Card({
            title = "What to show", icon = "healerWatchDrink", switch = false,
            what = "The healer's measured mana, confirmed drinking, and recent mana messages, each shown as what it is.",
            summary = function()
                local parts = { Label("manaFormat") }
                if hw.Get("showBar") then parts[#parts + 1] = "bar" end
                parts[#parts + 1] = ("low below %d%%, critical below %d%%"):format(hw.Thresholds().low, hw.Thresholds().critical)
                parts[#parts + 1] = hw.Get("chatDisplay") == "off" and "chat off" or ("chat for %ds"):format(hw.Get("chatExpiry"))
                return table.concat(parts, DOT)
            end,
            consequence = "A cup means the game shows a drinking aura on them; a faded cup means drinking can't be seen right now. A speech bubble means they said one of your phrases: it is never taken as a mana reading or as drinking. The flask is decoration; the bar and the number are the measured mana.",
            details = {
                { "How do the thresholds work?", "Low begins when mana drops below the low threshold and ends only when it is back at or above the low clear point; the same for critical. The gap stops the panel flickering when mana hovers at a threshold. Critical can't be set above low, and each clear point is kept at or above its threshold: the summary shows the values in use." },
                { "Which chat is listened to?", "Only the channels ticked below, and only messages the game says came from the watched healer. Other public channels are never looked at, nothing is kept after a message expires, and nothing is ever sent." },
            },
        })
        Check("showName", "Show the healer's name", "The healer's name at the top of the panel.")
        Pick("manaFormat", "Mana number", "How the measured mana is written. When it can't be read, \"--\" is shown, never 0%.")
        Check("showBar", "Show a mana bar", "A bar filled to the measured mana, in the mana color, turning to the low and critical colors.")
        Check("showManaState", "Say \"Low mana\" and \"Critical mana\"", "Writes the state in the status line too, so it is never told by color alone.")
        local function Effective() return hw.Thresholds() end
        K.Note(Range("lowAt", "Low mana below (%)", "Low mana begins when the measured mana drops below this percentage."), function()
            local t = Effective()
            if t.low ~= hw.Get("lowAt") then return ("In use: %d%%."):format(t.low) end
        end)
        K.Note(Range("lowClear", "Low mana ends at (%)", "Low mana ends only when mana is back at or above this percentage. Kept at or above the low threshold."), function()
            local t = Effective()
            if t.lowClear ~= hw.Get("lowClear") then return ("In use: %d%% (it can't be below the low threshold)."):format(t.lowClear) end
        end)
        K.Note(Range("criticalAt", "Critical mana below (%)", "Critical mana begins when the measured mana drops below this percentage. It can't be above the low threshold."), function()
            local t = Effective()
            if t.critical ~= hw.Get("criticalAt") then return ("In use: %d%% (it can't be above the low threshold)."):format(t.critical) end
        end)
        K.Note(Range("criticalClear", "Critical mana ends at (%)", "Critical mana ends only when mana is back at or above this percentage. Kept between the critical threshold and the low clear point."), function()
            local t = Effective()
            if t.criticalClear ~= hw.Get("criticalClear") then return ("In use: %d%%."):format(t.criticalClear) end
        end)
        Check("showDrinking", "Mark confirmed drinking", "A cup when the game shows a drinking aura on the healer, and a faded cup while auras can't be seen. Sitting, rising mana or a message never count as drinking.")
        Pick("chatDisplay", "Mana messages in chat", "Mark and words shows the speech bubble and a short, cleaned excerpt of what they said; Mark only shows the bubble and \"Mana message\"; Nothing stops listening to chat.")
        local function ChatOn() return On() and hw.Get("chatDisplay") ~= "off" end
        local chatWhy = "Greyed out: chat is set to Nothing."
        Check("chatParty", "Listen to party and raid chat", "Messages from the watched healer in party or raid chat (and from the party or raid leader).", ChatOn, chatWhy)
        Check("chatInstance", "Listen to instance chat", "Messages from the watched healer in instance chat, which groups made by the group finder use.", ChatOn, chatWhy)
        Check("chatSay", "Listen to /say", "Messages the watched healer says nearby. Off by default.", ChatOn, chatWhy)
        Check("chatWhisper", "Listen to their whispers to you", "Whispers the watched healer sends you. Off by default; whispers from anyone else are never looked at.", ChatOn, chatWhy)
        Range("chatExpiry", "Keep a message for (seconds)", "How long a mana message stays on the panel. It then simply goes away: nothing later is taken to mean they are ready.", ChatOn, chatWhy)
        Check("showElapsed", "Show how long ago it was said", "Adds \"4s ago\" after the message, updated once a second while it shows.", ChatOn, chatWhy)
        local sound = Check("chatSound", "Play a sound when a message arrives", "Plays the chosen sound once when a new mana message begins while the panel is shown. At least 15 seconds pass between two sounds, and a repeated message makes none. Off by default.", ChatOn, chatWhy)
        local function SoundOn() return ChatOn() and hw.Get("chatSound") end
        Under(K.Dropdown(Setting("chatSoundName", STRING, "Sound"), function() return R:SoundChoices(hw.Get("chatSoundName")) end,
            "TwichUI's own sounds, then every sound LibSharedMedia lists. A sound that has gone plays the default instead and stays chosen."), sound, SoundOn, "Greyed out: turn the sound on first.")

        -- 3. When to show
        K.Card({
            title = "When to show", icon = "reminderWhen", switch = false,
            what = "Where Healer Watch applies, and whether the panel is up all the time or only when something needs your attention.",
            summary = function()
                local parts = { ScopeLabel(), Label("visibility") }
                if not hw.Get("showInCombat") then parts[#parts + 1] = "hidden in combat" end
                if not hw.Get("showOutOfCombat") then parts[#parts + 1] = "hidden out of combat" end
                return table.concat(parts, DOT)
            end,
            consequence = "Where it applies is a gate, not an alert: outside it nothing is read. With \"Only when something needs attention\", any one ticked condition is enough to show the panel. Mana that can't be read never counts as low.",
        })
        Pick("visibility", "Show the panel", "Always shows it wherever it applies. Only when something needs attention keeps it hidden until any of the conditions ticked below is true.")
        local function Attention() return On() and hw.Get("visibility") == "attention" end
        local attWhy = "Greyed out: these apply with \"Only when something needs attention\"."
        Check("attnLow", "Low mana (includes critical)", "Shows the panel while measured mana is low or critical.", Attention, attWhy)
        Check("attnCritical", "Critical mana", "Shows the panel while measured mana is critical.", Attention, attWhy)
        Check("attnDrinking", "Confirmed drinking", "Shows the panel while the game shows a drinking aura on the healer.", Attention, attWhy)
        Check("attnChat", "A recent mana message", "Shows the panel while a mana message from the healer is current.", Attention, attWhy)
        Pick("scope", "Where it applies", "Five-player dungeons is the default. Dungeons and raids adds raid instances. Anywhere in a group and Anywhere, even alone, are for other group content and for trying it out; they are labelled so.")
        Check("showInCombat", "Show in combat", "Off hides the panel while you are in combat.")
        Check("showOutOfCombat", "Show out of combat", "Off hides the panel while you are out of combat.")
        Check("showSetup", "Keep \"Choose a healer\" on screen during play", "When nobody can be watched (no Healer role, several, or your choice left), the panel stays up to say so. Off by default: this page says it instead.")

        -- 4. Appearance and testing
        K.Card({
            title = "Appearance and testing", icon = "appearance", switch = false,
            what = "The panel's layout, size, text and colors. A preview, scenarios, the chat phrases and live diagnostics follow this card.",
            summary = function()
                return table.concat({ Label("preset"), ("%d%%"):format(hw.Get("scale")), ("opacity %d%%"):format(hw.Get("opacity")) }, DOT)
            end,
            consequence = "The panel never takes clicks, so it can't get in the way of the world; only the handle in Move it does. Motion is off unless you turn it on, and Notifications' Reduced motion turns it off again.",
        })
        Pick("preset", "Layout", "Compact: a small flask, the name, the mana and a bar, with a status line. Minimal: the mana with small marks. Artwork: a larger flask with the mana beneath. Choosing one sets the size and parts that suit it; you can change any of them afterwards.",
            nil, nil, nil, function(v)
                hw.ApplyPreset(v)
                for _, e in ipairs(resettable) do pcall(e.setting.NotifyUpdate, e.setting) end
            end)
        Range("scale", "Scale (%)", "Makes the whole panel bigger or smaller.")
        Range("opacity", "Opacity (%)", "How solid the panel is as a whole.")
        Check("showArt", "Show the flask", "The mana flask artwork. It is an emblem: its painted level never changes and is not a gauge.")
        Range("width", "Width", "The panel's width (Compact), or the column's (Artwork). Minimal fits its contents.")
        Range("barHeight", "Bar height", "How tall the mana bar is.")
        Range("artSize", "Flask size", "The flask's size; it keeps its shape.")
        Under(K.Dropdown(Setting("font", STRING, "Font"), function() return MS.Fonts.Choices(hw.Get("font"), { { "default", "Game font (default)" } }) end,
            "The panel's typeface. Fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's are listed. A font that has gone is drawn with the game's own and stays chosen."), main, On)
        Range("textSize", "Text size", "The size of the name and the number; the status line is drawn a little smaller.")
        Pick("outline", "Text outline", "Outline keeps the words readable over any scenery; Shadow is a soft dark edge; None leaves them bare.")
        Pick("statusPlace", "Status line", "Whether the status line sits below the bar or above it (Compact).")
        Swatch("colorMana", "Mana color", "The bar's color while mana is fine.")
        Swatch("colorLow", "Low mana color", "The bar's and the number's color while mana is low; also used for \"Choose a healer\".")
        Swatch("colorCritical", "Critical mana color", "The bar's and the number's color while mana is critical.")
        Swatch("colorText", "Text color", "The name and the number.")
        Swatch("colorDim", "Secondary text color", "The status line and readings that can't be trusted.")
        Under(K.Dropdown(Setting("barTexture", STRING, "Mana bar texture"),
            function() return MS.StatusBars.Choices(hw.Get("barTexture")) end,
            "The picture the bar is filled with, tinted by the mana, low and critical colors. Flat color is a plain fill; the rest are EllesmereUI's bar textures while it is installed and every LibSharedMedia status bar texture. A texture that has gone is drawn flat and stays chosen."), main, On)
        Check("barBorder", "Border round the mana bar", "A line round the bar. Off draws none. Its texture, thickness, color and opacity are the next four settings.")
        local function BorderOn() return On() and hw.Get("barBorder") end
        for _, e in ipairs(K.Appearance(hw.BarLook, "healerWatchBar", "mana bar", nil, nil, nil, nil, main, BorderOn, {
            order = hw.BAR_BORDER_KEYS,
            labels = { BorderTexture = "Mana bar border texture", BorderSize = "Mana bar border thickness",
                BorderColor = "Mana bar border color", BorderOpacity = "Mana bar border opacity" },
            decorate = function(_, row) row.why = "Greyed out: turn on \"Border round the mana bar\" first." end })) do
            resettable[#resettable + 1] = e
        end
        Range("panelBg", "Background (%)", "A dark wash behind the whole panel, for reading over bright scenery. 0 for none (the default).")
        Check("panelBorder", "Border round the panel", "A thin bronze line round the whole panel.")
        Check("fade", "Fade in and out", "A short fade when the panel appears and goes. Off with Notifications' Reduced motion.")
        local NOTE = " None by default. Neither effect plays with Notifications' Reduced motion. The panel's words and numbers say the same thing with or without it."
        Pick("effectChat", "Attention effect: they say something", "What draws the eye when a mana message from the healer begins. Flash: a short bright flash of the panel, twice (at least two seconds apart). Magical particles: a few soft motes drift off the panel's edges and fade, without flashing it." .. NOTE)
        Pick("effectCritical", "Attention effect: mana becomes critical", "What draws the eye when measured mana drops into critical (a flash is in the critical color). Never from mana the game keeps from addons." .. NOTE)
        Pick("effectDrinking", "Attention effect: drinking is confirmed", "What draws the eye when a drinking aura appears on the healer (a flash is in the mana color). Magical particles keep coming, a burst and a short rest at a time, for as long as they are confirmed drinking; a flash plays once." .. NOTE)
        local function Particles()
            return On() and (hw.Get("effectChat") == "particles" or hw.Get("effectCritical") == "particles" or hw.Get("effectDrinking") == "particles")
        end
        local particlesWhy = "Greyed out: choose Magical particles for one of the attention effects above."
        Under(K.Swatch(Setting("particleColor", STRING, "Particle color"),
            "The color of the motes and the faint glow along the panel's edge. It tints only the particles, never the bar, the name or the status. Arcane teal by default."), main, Particles, particlesWhy)
        Pick("particleIntensity", "Particle strength", "How many motes and how clear the edge glow is. Each burst is brief and repeated triggers are folded into one.", nil, Particles, particlesWhy)
        Under(K.Button("Preview particles", "Preview", function()
            local ok, why = P.PlayParticles()
            if not ok then
                local text = why == "motion" and "Nothing played: Reduced motion is on in Notifications." or "Open the sample below first."
                Say(text, "warn")
                R.Print("%s", text)
            end
        end, "Plays one burst on the sample below, in the chosen color and strength, whatever the effects above are set to. It reads nothing from your group and changes nothing. It never plays with Notifications' Reduced motion."), main, On)
        Check("pulse", "Pulse once when mana becomes critical", "Three slow breaths, then still; never a pulse that keeps going. Off with Notifications' Reduced motion.")
        Pick("point", "Anchor", "The point of the screen the panel is placed from. Moving the panel keeps this anchor.")
        Range("x", "Horizontal offset", "Screen units from the anchor, to the right (negative: to the left).")
        Range("y", "Vertical offset", "Screen units from the anchor, upwards (negative: downwards).")
        Under(K.Button("Reset position", "Reset", function() Wt.ResetPosition() end,
            "Puts the panel back at its default place, left of and below the middle of the screen. Only the place changes."), main, On)
        K.ResetButton("Healer Watch settings", resettable, function() hw.ResetSettings() end,
            "Puts the settings on this page back to their defaults, the mana bar's border included. The switch, the panel's place, your chat phrases and the healer you chose are kept.")
    end,
    host = function() return P.Frame() end, hostAfter = "Appearance and testing", hostHeight = function() return P.Height() end,
})
