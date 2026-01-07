local T = unpack(Twich)
local L = T.L or function(s) return s end

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

---@class MythicPlusScoreSimulatorSubmodule
local ScoreSimulator = MythicPlusModule.ScoreSimulator or {}
MythicPlusModule.ScoreSimulator = ScoreSimulator

local ScoreCalculator = MythicPlusModule.ScoreCalculator
local Data = MythicPlusModule.Data

---@type ToolsModule
local Tools = T:GetModule("Tools")
---@type ToolsUI|nil
local UI = Tools and Tools.UI
---@type table|nil
local CT = Tools and Tools.Colors

local _G = _G
local ElvUI = _G.ElvUI
local E = ElvUI and ElvUI[1]

-- print("DEBUG: ScoreSimulator Loaded. E is " .. tostring(E)) -- Debug

local CreateFrame = _G.CreateFrame
local UIDropDownMenu_CreateInfo = _G.UIDropDownMenu_CreateInfo
local UIDropDownMenu_AddButton = _G.UIDropDownMenu_AddButton
local UIDropDownMenu_SetText = _G.UIDropDownMenu_SetText
local UIDropDownMenu_SetSelectedValue = _G.UIDropDownMenu_SetSelectedValue
local UIDropDownMenu_Initialize = _G.UIDropDownMenu_Initialize
local CloseDropDownMenus = _G.CloseDropDownMenus
local ToggleDropDownMenu = _G.ToggleDropDownMenu
local C_ChallengeMode = _G.C_ChallengeMode

-- Constants
local ICON_PATH = "Interface\\AddOns\\TwichUI\\Media\\Textures\\score-simulator.tga"
local PANEL_ID = "score_simulator"
local LABEL_TEXT = "Score\nSimulator"

local MAP_DROPDOWN_WIDTH = 260

---@class ScoreSimulatorFrame : Frame
---@field dungeonDropdown Frame
---@field levelEditBox EditBox
---@field timeEditBox EditBox
---@field resultText FontString
---@field detailsText FontString
---@field baseScoreText FontString
---@field timeBonusText FontString
---@field affixBonusText FontString
---@field currentRunText FontString
---@field currentScoreText FontString
---@field diffText FontString

-- State
local selectedMapId = nil
local selectedChest = 1 -- 1: +1 (Timed), 2: +2, 3: +3, 0: Overtime
local currentKeystoneLevel = 2

-- Helper for colors
local function GetColor(key)
    if CT and CT.TWICH and CT.TWICH[key] then
        local hex = CT.TWICH[key]
        if type(hex) == "string" and hex:sub(1, 1) == "#" then
            local r = tonumber(hex:sub(2, 3), 16) or 255
            local g = tonumber(hex:sub(4, 5), 16) or 255
            local b = tonumber(hex:sub(6, 7), 16) or 255
            return r / 255, g / 255, b / 255
        end
    end
    return 1, 1, 1
end

local COLOR_PRIMARY = { GetColor("TEXT_PRIMARY") }
local COLOR_MUTED = { GetColor("TEXT_MUTED") }
local COLOR_ACCENT = { GetColor("SECONDARY_ACCENT") }

-- Helper for font
local function SetFont(fontString, style)
    if not fontString then return end
    -- Fallback to standard objects
    if style == "huge" then
        fontString:SetFontObject("GameFontNormalHuge")
    elseif style == "large" then
        fontString:SetFontObject("GameFontNormalLarge")
    elseif style == "small" then
        fontString:SetFontObject("GameFontNormalSmall")
    else
        fontString:SetFontObject("GameFontNormal")
    end
end

-- Helper to format seconds to MM:SS
local function FormatTime(seconds)
    if not seconds then return "" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function GetMapList()
    -- Prefer current season maps (safe/cached), then fall back to ChallengeMode table.
    local maps
    if Data and type(Data.GetCurrentSeasonMapsCached) == "function" then
        local ok, result = pcall(Data.GetCurrentSeasonMapsCached)
        if ok then
            maps = result
        end
    end
    if not maps and C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" then
        local ok, m = pcall(C_ChallengeMode.GetMapTable)
        if ok then
            maps = m
        end
    end

    if type(maps) ~= "table" then
        maps = nil
    end

    local list = {}
    if maps then
        for _, entry in ipairs(maps) do
            local id
            local name

            if type(entry) == "table" then
                id = entry.id or entry.mapId or entry.challengeMapID
                name = entry.name or entry.mapName
            else
                id = entry
            end

            if type(id) ~= "number" then
                -- Skip unexpected entries instead of hard erroring.
            else
                if C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
                    local ok, n = pcall(C_ChallengeMode.GetMapUIInfo, id)
                    if ok then
                        name = n
                    end
                end
                if name then
                    table.insert(list, { id = id, name = name })
                else
                    -- Still insert the id so the dropdown isn't empty; name can be resolved later.
                    table.insert(list, { id = id, name = tostring(id) })
                end
            end
        end
    end
    -- Sort by name
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local CHEST_OPTIONS = {
    { value = 3, text = "+3" },   -- < 60% time
    { value = 2, text = "+2" },   -- < 80% time
    { value = 1, text = "+1" },   -- < 100% time
    { value = 0, text = "Over" }, -- > 100% time
}

function ScoreSimulator:UpdateSimulation(frame)
    if not frame then return end

    local function Round0(x)
        x = tonumber(x)
        if not x then return 0 end
        if x >= 0 then
            return math.floor(x + 0.5)
        end
        return math.ceil(x - 0.5)
    end

    local level = tonumber(frame.levelEditBox:GetText()) or 2

    if not selectedMapId then
        frame.resultText:SetText("-")
        frame.baseScoreText:SetText("")
        frame.affixBonusText:SetText("")
        frame.timeBonusText:SetText("")
        frame.currentScoreText:SetText("")
        frame.currentRunText:SetText("")
        if frame.projectedTotalText then
            frame.projectedTotalText:SetText("")
        end
        frame.diffText:SetText("")
        frame.timerText:SetText("")
        return
    end

    -- Calculate time based on chest selection
    local parTime = ScoreCalculator.GetParTimeSeconds(selectedMapId)
    local timeSec = nil

    if parTime then
        if selectedChest == 3 then
            timeSec = parTime * 0.6 - 1 -- Just under 60%
        elseif selectedChest == 2 then
            timeSec = parTime * 0.8 - 1 -- Just under 80%
        elseif selectedChest == 1 then
            timeSec = parTime * 0.99    -- Just under 100%
        else
            timeSec = parTime * 1.01    -- Overtime
        end
    end

    -- Show simulated time
    if timeSec then
        frame.timerText:SetText(string.format("Simulating Run Time: %s", FormatTime(timeSec)))
    else
        frame.timerText:SetText("No Par Time Data")
    end

    local score, details = ScoreCalculator.CalculateForRun(selectedMapId, level, timeSec)

    -- Update UI
    frame.resultText:SetText(Round0(score))
    frame.resultText:SetTextColor(COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3])

    if details then
        frame.baseScoreText:SetText(string.format("Base: %d", Round0(details.baseScore or 0)))
        frame.affixBonusText:SetText(string.format("Affixes: %d", Round0(details.affixBonus or 0)))
        frame.timeBonusText:SetText(string.format("Time: %d", Round0(details.timeBonus or 0)))
    end

    -- Compare with current best
    local currentScore, currentRun = ScoreCalculator.TryGetBlizzardRunScore(selectedMapId, nil, nil)

    -- Overall / projected total score
    do
        local totalText = frame.projectedTotalText
        if totalText then
            local C_ChallengeMode = _G.C_ChallengeMode
            local overall = (C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function")
                and tonumber(C_ChallengeMode.GetOverallDungeonScore())
                or nil

            if overall and overall > 0 then
                local baseMapScore = (currentScore and currentScore > 0) and currentScore or 0
                local projected = overall - baseMapScore + (tonumber(score) or 0)
                totalText:SetText(string.format("Projected Total: %d", Round0(projected)))
            else
                totalText:SetText("Projected Total: N/A")
            end
        end
    end

    if currentScore and currentScore > 0 then
        frame.currentScoreText:SetText(string.format("Current Best: %d", Round0(currentScore)))
        if currentRun then
            local runLevel = currentRun.level or currentRun.keystoneLevel
            frame.currentRunText:SetText(string.format("(Level %d)", runLevel))
        else
            frame.currentRunText:SetText("")
        end

        -- Delta
        local diff = Round0(score) - Round0(currentScore)
        if diff > 0 then
            frame.diffText:SetText(string.format("+%d", diff))
            frame.diffText:SetTextColor(0, 1, 0)
        elseif diff < 0 then
            frame.diffText:SetText(string.format("%d", diff))
            frame.diffText:SetTextColor(1, 0, 0)
        else
            frame.diffText:SetText("=")
            frame.diffText:SetTextColor(0.5, 0.5, 0.5)
        end
    else
        frame.currentScoreText:SetText("Current Best: None")
        frame.currentRunText:SetText("")
        frame.diffText:SetText("")
    end
end

function ScoreSimulator:CreateSimulatorFrame(parent, window)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local function Dbg(msg)
        if _G.print then
            _G.print("TwichUI ScoreSim:", tostring(msg))
        end
    end

    local function Err(msg)
        if _G.print then
            _G.print("TwichUI ScoreSim ERROR:", tostring(msg))
        end
        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
            _G.UIErrorsFrame:AddMessage("TwichUI ScoreSim: " .. tostring(msg), 1, 0.2, 0.2)
        end
    end

    local function SafeCall(label, fn)
        local ok, err = pcall(fn)
        if not ok then
            Err(label .. " failed: " .. tostring(err))
            if type(_G.debugstack) == "function" then
                Err(_G.debugstack())
            end
        end
        return ok
    end

    local function StripDropDown(dropdown)
        if not dropdown or type(dropdown.GetName) ~= "function" then return end

        local ddName = dropdown:GetName()
        if ddName then
            local left = _G[ddName .. "Left"]
            local middle = _G[ddName .. "Middle"]
            local right = _G[ddName .. "Right"]
            if left then left:Hide() end
            if middle then middle:Hide() end
            if right then right:Hide() end

            local button = _G[ddName .. "Button"]
            if button then
                -- Some skins/clients anchor the button to the "Right" texture; if we hide it,
                -- the button (and any text anchored to it) can collapse into the left side.
                button:ClearAllPoints()
                button:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)

                -- Keep the button clickable, but strip ALL visuals (arrow, highlights, etc).
                local nt = button.GetNormalTexture and button:GetNormalTexture() or nil
                local pt = button.GetPushedTexture and button:GetPushedTexture() or nil
                local dt = button.GetDisabledTexture and button:GetDisabledTexture() or nil
                local ht = button.GetHighlightTexture and button:GetHighlightTexture() or nil
                if nt then
                    nt:SetTexture(nil)
                    nt:Hide()
                end
                if pt then
                    pt:SetTexture(nil)
                    pt:Hide()
                end
                if dt then
                    dt:SetTexture(nil)
                    dt:Hide()
                end
                if ht then
                    ht:SetTexture(nil)
                    ht:Hide()
                end
                -- NOTE: In modern clients, SetNormalTexture/SetPushedTexture/etc do NOT accept nil.
                -- Hiding the existing textures is enough and avoids "Usage: self:SetNormalTexture(asset)" errors.
            end

            local text = _G[ddName .. "Text"]
            if text then
                text:ClearAllPoints()
                text:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
                -- Anchor to the dropdown itself (not the arrow button) so the label doesn't
                -- collapse down to a single visible character after skinning.
                text:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
            end
        end
    end

    local function MakeDropDownFullClickable(dropdown)
        if not dropdown then return end
        dropdown:EnableMouse(true)

        local function Open()
            local toggle = _G.ToggleDropDownMenu or ToggleDropDownMenu
            if type(toggle) == "function" then
                -- Use explicit level/anchor args; nil,nil can fail depending on template/state.
                toggle(1, nil, dropdown, dropdown, 0, 0)
            else
                Err("ToggleDropDownMenu is not available")
            end
        end

        -- 1) Direct click on dropdown frame
        dropdown:SetScript("OnMouseDown", function()
            Dbg("Dropdown mouse down: " .. tostring(dropdown:GetName() or "<unnamed>"))
            Open()
        end)

        -- 2) IMPORTANT: Do NOT use a full overlay button here.
        -- It can extend beyond the visible dropdown and block adjacent controls (like the level edit box).
        if dropdown._twichuiOverlayButton then
            dropdown._twichuiOverlayButton:EnableMouse(false)
            dropdown._twichuiOverlayButton:Hide()
        end
    end

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY")
    SetFont(title, "large")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -20)
    title:SetText("Mythic+ Score Simulator")
    title:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

    -- Description
    local desc = frame:CreateFontString(nil, "OVERLAY")
    SetFont(desc, "small")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    desc:SetWidth(500)
    desc:SetJustifyH("LEFT")
    desc:SetText("Select dungeon and desired chest result. (v2)")
    desc:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])

    Dbg("CreateSimulatorFrame start")

    -- 1. Configuration Panel (Top Row)
    local configPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    configPanel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    configPanel:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    configPanel:SetHeight(80)

    configPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    configPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    configPanel:SetBackdropBorderColor(0, 0, 0, 1)

    -- Dungeon Dropdown
    -- Parent to frame (Main Window) instead of configPanel to avoid clipping/level issues
    local mapDropdown = CreateFrame("Frame", "TwichUIScoreSimMapDropdown", frame, "UIDropDownMenuTemplate")
    mapDropdown:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 10, -25)
    mapDropdown:SetFrameLevel(frame:GetFrameLevel() + 100)
    SafeCall("Setup map dropdown", function()
        if mapDropdown.SetWidth then mapDropdown:SetWidth(MAP_DROPDOWN_WIDTH) end
        if type(_G.UIDropDownMenu_SetWidth) == "function" then _G.UIDropDownMenu_SetWidth(mapDropdown, MAP_DROPDOWN_WIDTH) end
        if type(_G.UIDropDownMenu_SetButtonWidth) == "function" then
            _G.UIDropDownMenu_SetButtonWidth(mapDropdown,
                MAP_DROPDOWN_WIDTH)
        end
        if type(UIDropDownMenu_SetText) == "function" then UIDropDownMenu_SetText(mapDropdown, "Select Dungeon") end
        if type(UIDropDownMenu_JustifyText) == "function" then UIDropDownMenu_JustifyText(mapDropdown, "LEFT") end
    end)
    Dbg("Map dropdown created")

    local okSkinMap = SafeCall("Skin map dropdown", function()
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleDropDownBox then
                S:HandleDropDownBox(mapDropdown)
            end
        end

        -- Some skins reset width; enforce after skinning.
        if mapDropdown.SetWidth then mapDropdown:SetWidth(MAP_DROPDOWN_WIDTH) end
        if type(_G.UIDropDownMenu_SetWidth) == "function" then _G.UIDropDownMenu_SetWidth(mapDropdown, MAP_DROPDOWN_WIDTH) end
        if type(_G.UIDropDownMenu_SetButtonWidth) == "function" then
            _G.UIDropDownMenu_SetButtonWidth(mapDropdown,
                MAP_DROPDOWN_WIDTH)
        end
    end)
    if okSkinMap then Dbg("Map dropdown skinned") end

    local okStripMap = SafeCall("Strip map dropdown", function()
        StripDropDown(mapDropdown)
    end)
    if okStripMap then Dbg("Map dropdown stripped") end

    local okClickMap = SafeCall("Make map dropdown clickable", function()
        MakeDropDownFullClickable(mapDropdown)
    end)
    if okClickMap then Dbg("Map dropdown clickable") end

    local mapLabel = configPanel:CreateFontString(nil, "OVERLAY")
    SetFont(mapLabel)
    -- Align label to the dropdown's effective visual area
    mapLabel:SetPoint("BOTTOMLEFT", mapDropdown, "TOPLEFT", 15, 5) -- Adjusted to match visual center
    mapLabel:SetText("Dungeon")
    mapLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

    local mapList = {}
    SafeCall("GetMapList", function()
        mapList = GetMapList() or {}
    end)
    Dbg("Map list size: " .. tostring(#mapList))
    SafeCall("UIDropDownMenu_Initialize(mapDropdown)", function()
        local ddInit = _G.UIDropDownMenu_Initialize or UIDropDownMenu_Initialize
        local ddCreateInfo = _G.UIDropDownMenu_CreateInfo or UIDropDownMenu_CreateInfo
        local ddAddButton = _G.UIDropDownMenu_AddButton or UIDropDownMenu_AddButton
        local ddSetSelectedValue = _G.UIDropDownMenu_SetSelectedValue or UIDropDownMenu_SetSelectedValue
        local ddSetText = _G.UIDropDownMenu_SetText or UIDropDownMenu_SetText

        if type(ddInit) ~= "function" or type(ddCreateInfo) ~= "function" or type(ddAddButton) ~= "function" then
            Err("UIDropDownMenu API missing; cannot initialize dungeon dropdown")
            return
        end

        ddInit(mapDropdown, function(self, level)
            level = level or 1
            for _, map in ipairs(mapList) do
                local mapId = map.id
                local mapName = map.name
                local info = ddCreateInfo()
                info.text = mapName
                info.arg1 = mapId
                info.arg2 = mapName
                info.func = function(_, arg1, arg2)
                    selectedMapId = arg1
                    if type(ddSetSelectedValue) == "function" then ddSetSelectedValue(mapDropdown, arg1) end
                    if type(ddSetText) == "function" then ddSetText(mapDropdown, arg2) end
                    ScoreSimulator:UpdateSimulation(frame)
                end
                ddAddButton(info, level)
            end

            if #mapList == 0 then
                local info = ddCreateInfo()
                info.text = "No dungeons found"
                info.notCheckable = true
                info.disabled = true
                ddAddButton(info, level)
            end
        end)
    end)
    frame.dungeonDropdown = mapDropdown
    -- Note: Skinning handled above inline to ensure order

    -- Level Input
    local levelInput
    SafeCall("Create level input", function()
        levelInput = CreateFrame("EditBox", nil, configPanel, "InputBoxTemplate")
        levelInput:SetSize(40, 20)
        levelInput:SetPoint("LEFT", mapDropdown, "RIGHT", 12, 2)
        levelInput:SetAutoFocus(false)
        levelInput:SetNumeric(true)
        levelInput:SetText("2")
        levelInput:SetJustifyH("CENTER")
        levelInput:SetScript("OnTextChanged", function() ScoreSimulator:UpdateSimulation(frame) end)
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleEditBox then S:HandleEditBox(levelInput) end
        end
        frame.levelEditBox = levelInput
        Dbg("Created level input")

        local levelLabel = configPanel:CreateFontString(nil, "OVERLAY")
        SetFont(levelLabel)
        levelLabel:SetPoint("BOTTOM", levelInput, "TOP", 0, 5)
        levelLabel:SetText("Level")
        levelLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    end)

    -- Chest Selection
    -- Parent to frame (Main Window)
    local chestDropdown
    SafeCall("Create chest dropdown", function()
        if not levelInput then
            Err("Level input missing; anchoring chest dropdown to map dropdown")
        end

        chestDropdown = CreateFrame("Frame", "TwichUIScoreSimChestDropdown", frame, "UIDropDownMenuTemplate")
        chestDropdown:SetPoint("LEFT", (levelInput or mapDropdown), "RIGHT", 12, (levelInput and -2 or 2))
        chestDropdown:SetFrameLevel(frame:GetFrameLevel() + 100)
        UIDropDownMenu_SetWidth(chestDropdown, 100)
        UIDropDownMenu_SetText(chestDropdown, "+1")
        UIDropDownMenu_JustifyText(chestDropdown, "LEFT")

        if E then
            local S = E:GetModule("Skins")
            if S then S:HandleDropDownBox(chestDropdown) end
        end

        StripDropDown(chestDropdown)
        MakeDropDownFullClickable(chestDropdown)

        local chestLabel = configPanel:CreateFontString(nil, "OVERLAY")
        SetFont(chestLabel)
        chestLabel:SetPoint("BOTTOMLEFT", chestDropdown, "TOPLEFT", 15, 5)
        chestLabel:SetText("Result")
        chestLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

        SafeCall("UIDropDownMenu_Initialize(chestDropdown)", function()
            local ddInit = _G.UIDropDownMenu_Initialize or UIDropDownMenu_Initialize
            local ddCreateInfo = _G.UIDropDownMenu_CreateInfo or UIDropDownMenu_CreateInfo
            local ddAddButton = _G.UIDropDownMenu_AddButton or UIDropDownMenu_AddButton
            local ddSetSelectedValue = _G.UIDropDownMenu_SetSelectedValue or UIDropDownMenu_SetSelectedValue
            local ddSetText = _G.UIDropDownMenu_SetText or UIDropDownMenu_SetText

            if type(ddInit) ~= "function" or type(ddCreateInfo) ~= "function" or type(ddAddButton) ~= "function" then
                Err("UIDropDownMenu API missing; cannot initialize result dropdown")
                return
            end

            ddInit(chestDropdown, function(self, level)
                level = level or 1
                for _, opt in ipairs(CHEST_OPTIONS) do
                    local optText = opt.text
                    local optValue = opt.value
                    local info = ddCreateInfo()
                    info.text = optText
                    info.arg1 = optValue
                    info.arg2 = optText
                    info.func = function(_, arg1, arg2)
                        selectedChest = arg1
                        if type(ddSetSelectedValue) == "function" then ddSetSelectedValue(chestDropdown, arg1) end
                        if type(ddSetText) == "function" then ddSetText(chestDropdown, arg2) end
                        ScoreSimulator:UpdateSimulation(frame)
                    end
                    ddAddButton(info, level)
                end
            end)
        end)

        frame.chestDropdown = chestDropdown
        Dbg("Created chest dropdown")
    end)
    -- Skinning done inline above

    -- 2. Results Panel (Bottom, Full Width)
    local resultsPanel
    SafeCall("Create results panel", function()
        resultsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        resultsPanel:SetPoint("TOPLEFT", configPanel, "BOTTOMLEFT", 0, -10)
        resultsPanel:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
        resultsPanel:SetHeight(150)

        resultsPanel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        resultsPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        resultsPanel:SetBackdropBorderColor(0, 0, 0, 1)
        Dbg("Created results panel")
    end)

    if not resultsPanel then
        Err("Results panel missing; simulator UI will be incomplete")
        return frame
    end

    -- Projected Score (Large)
    local scoreLabel = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(scoreLabel, "normal")
    scoreLabel:SetPoint("TOPLEFT", resultsPanel, "TOPLEFT", 20, -20)
    scoreLabel:SetText("PROJECTED SCORE")
    scoreLabel:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])

    local resultValue = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(resultValue, "huge")
    resultValue:SetPoint("TOPLEFT", scoreLabel, "BOTTOMLEFT", 0, -10)
    resultValue:SetText("-")
    frame.resultText = resultValue

    -- Comparison (Next to it)
    local diffText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(diffText, "large")
    diffText:SetPoint("LEFT", resultValue, "RIGHT", 10, 0)
    diffText:SetText("")
    frame.diffText = diffText

    -- Simulation Information (Timer)
    local timerText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(timerText, "small")
    timerText:SetPoint("TOPLEFT", resultValue, "BOTTOMLEFT", 0, -15)
    timerText:SetText("")
    timerText:SetTextColor(0.6, 0.6, 0.6)
    frame.timerText = timerText

    -- Details (Right Side of Results Panel)
    local detailsX = 300

    frame.baseScoreText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(frame.baseScoreText)
    frame.baseScoreText:SetPoint("TOPLEFT", resultsPanel, "TOPLEFT", detailsX, -25)
    frame.baseScoreText:SetTextColor(0.8, 0.8, 0.8)

    frame.affixBonusText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(frame.affixBonusText)
    frame.affixBonusText:SetPoint("TOPLEFT", frame.baseScoreText, "BOTTOMLEFT", 0, -8)
    frame.affixBonusText:SetTextColor(0.8, 0.8, 0.8)

    frame.timeBonusText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(frame.timeBonusText)
    frame.timeBonusText:SetPoint("TOPLEFT", frame.affixBonusText, "BOTTOMLEFT", 0, -8)
    frame.timeBonusText:SetTextColor(0.8, 0.8, 0.8)

    -- Current Best (Bottom)
    local separator = resultsPanel:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(1, 1, 1, 0.1)
    separator:SetHeight(1)
    separator:SetPoint("LEFT", resultsPanel, "LEFT", 10, 0)
    separator:SetPoint("RIGHT", resultsPanel, "RIGHT", -10, 0)
    separator:SetPoint("TOP", frame.timeBonusText, "BOTTOM", 0, -20)

    frame.currentScoreText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(frame.currentScoreText)
    frame.currentScoreText:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 10, -10)
    frame.currentScoreText:SetTextColor(0.7, 0.7, 0.7)

    frame.currentRunText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(frame.currentRunText)
    frame.currentRunText:SetPoint("LEFT", frame.currentScoreText, "RIGHT", 5, 0)
    frame.currentRunText:SetTextColor(0.5, 0.5, 0.5)

    frame.projectedTotalText = resultsPanel:CreateFontString(nil, "OVERLAY")
    SetFont(frame.projectedTotalText)
    frame.projectedTotalText:SetPoint("TOPLEFT", frame.currentScoreText, "BOTTOMLEFT", 0, -6)
    frame.projectedTotalText:SetTextColor(0.7, 0.7, 0.7)

    -- Initial update
    ScoreSimulator:UpdateSimulation(frame)

    return frame
end

function ScoreSimulator:Initialize()
    if self.initialized then return end
    self.initialized = true

    if _G.print then
        _G.print("TwichUI ScoreSim: Initialize")
    end

    local function TryRegister()
        if MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.RegisterPanel then
            MythicPlusModule.MainWindow:RegisterPanel(
                PANEL_ID,
                function(parent, window) return ScoreSimulator:CreateSimulatorFrame(parent, window) end,
                nil, -- OnShow
                nil, -- OnHide
                {
                    label = LABEL_TEXT,
                    order = 100,
                    icon = ICON_PATH,
                }
            )
            if _G.print then
                _G.print("TwichUI ScoreSim: Panel registered")
            end
            return true
        end
        return false
    end

    if not TryRegister() then
        if _G.print then
            _G.print("TwichUI ScoreSim: MainWindow not ready; retrying...")
        end
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(1, TryRegister)
            _G.C_Timer.After(3, TryRegister)
        end
    end
end

-- Safety: if Mythic+ is already enabled by the time this file loads, initialize now.
if MythicPlusModule and MythicPlusModule.IsEnabled and MythicPlusModule:IsEnabled() then
    ScoreSimulator:Initialize()
end
