-- Match the +1/+2/+3 chest timer colors used in the Dungeons panel.
local CHEST_TIME_COLORS = {
    [1] = { 0, 1, 0 },
    [2] = { 0, 0.44, 0.87 },
    [3] = { 0.64, 0.21, 0.93 },
}
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
local LABEL_TEXT = "Score"

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

local function ColorWrapInline(text, r, g, b)
    local rr = math.max(0, math.min(255, math.floor((tonumber(r) or 1) * 255 + 0.5)))
    local gg = math.max(0, math.min(255, math.floor((tonumber(g) or 1) * 255 + 0.5)))
    local bb = math.max(0, math.min(255, math.floor((tonumber(b) or 1) * 255 + 0.5)))
    return string.format("|cff%02x%02x%02x%s|r", rr, gg, bb, tostring(text or ""))
end

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

local function Round0(x)
    x = tonumber(x)
    if not x then return 0 end
    if x >= 0 then
        return math.floor(x + 0.5)
    end
    return math.ceil(x - 0.5)
end

local function GetScorePlannerDB()
    local profile = (T and T.db and T.db.profile)
    if type(profile) == "table" then
        profile.mythicPlus = profile.mythicPlus or {}
        profile.mythicPlus.scorePlanner = profile.mythicPlus.scorePlanner or {}
        return profile.mythicPlus.scorePlanner
    end
    return nil
end

local function SaveScorePlannerLastPlan(plan)
    local db = GetScorePlannerDB()
    if not db or type(plan) ~= "table" then return end

    local out = {
        overall = tonumber(plan.overall),
        desired = tonumber(plan.desired),
        needed = tonumber(plan.needed),
        totalGain = tonumber(plan.totalGain),
        projected = tonumber(plan.projected),
        picks = {},
        savedAt = (_G.time and _G.time()) or nil,
    }

    if type(plan.picks) == "table" then
        for i, opt in ipairs(plan.picks) do
            if i > 50 then break end
            out.picks[i] = {
                mapId = tonumber(opt.mapId),
                mapName = opt.mapName,
                level = tonumber(opt.level),
                chest = tonumber(opt.chest),
                timeSec = tonumber(opt.timeSec),
                gain = tonumber(opt.gain),
            }
        end
    end

    db.lastPlan = out
end

local function LoadScorePlannerLastPlan()
    local db = GetScorePlannerDB()
    if not db or type(db.lastPlan) ~= "table" then return nil end
    return db.lastPlan
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
        local api = MythicPlusModule and MythicPlusModule.API
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
                if api and type(api.GetMapUIInfo) == "function" then
                    local n = api:GetMapUIInfo(id)
                    if type(n) == "string" and n ~= "" then
                        name = n
                    end
                elseif C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
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
            local api = MythicPlusModule and MythicPlusModule.API
            local overall = (api and type(api.GetOverallDungeonScore) == "function") and api:GetOverallDungeonScore()
                or ((C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function")
                    and tonumber(C_ChallengeMode.GetOverallDungeonScore())
                    or nil)

            if overall and overall > 0 then
                local baseMapScore = (currentScore and currentScore > 0) and currentScore or 0
                local projected = overall - baseMapScore + (tonumber(score) or 0)
                local projectedRounded = Round0(projected)
                local deltaTotal = Round0(projectedRounded - Round0(overall))

                local deltaText
                if deltaTotal > 0 then
                    deltaText = ColorWrapInline("+" .. tostring(deltaTotal), 0, 1, 0)
                elseif deltaTotal < 0 then
                    deltaText = ColorWrapInline(tostring(deltaTotal), 1, 0.2, 0.2)
                else
                    deltaText = ColorWrapInline("=", 0.6, 0.6, 0.6)
                end

                totalText:SetText(
                    ColorWrapInline("Projected Total: ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                    .. ColorWrapInline(tostring(projectedRounded), COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3])
                    .. " ("
                    .. deltaText
                    .. ")"
                )
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
        do
            local left = (ddName and _G[ddName .. "Left"]) or dropdown.Left
            local middle = (ddName and _G[ddName .. "Middle"]) or dropdown.Middle
            local right = (ddName and _G[ddName .. "Right"]) or dropdown.Right
            if left then left:Hide() end
            if middle then middle:Hide() end
            if right then right:Hide() end

            local button = (ddName and _G[ddName .. "Button"]) or dropdown.Button
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

            local text = (ddName and _G[ddName .. "Text"]) or dropdown.Text
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
            Open()
        end)

        -- 2) IMPORTANT: Do NOT use a full overlay button here.
        -- It can extend beyond the visible dropdown and block adjacent controls (like the level edit box).
        if dropdown._twichuiOverlayButton then
            dropdown._twichuiOverlayButton:EnableMouse(false)
            dropdown._twichuiOverlayButton:Hide()
        end
    end

    -- Tabs
    local tabsBar = CreateFrame("Frame", nil, frame)
    tabsBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -8)
    tabsBar:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    tabsBar:SetHeight(28)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", tabsBar, "BOTTOMLEFT", 0, -6)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 12)

    local simPage = CreateFrame("Frame", nil, content)
    simPage:SetAllPoints(content)

    local plannerPage = CreateFrame("Frame", nil, content)
    plannerPage:SetAllPoints(content)

    -- Simulator tab heading
    local simTitle = simPage:CreateFontString(nil, "OVERLAY")
    SetFont(simTitle, "large")
    simTitle:SetPoint("TOPLEFT", simPage, "TOPLEFT", 0, 0)
    simTitle:SetText("Mythic+ Score Simulator")
    simTitle:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

    local simDesc = simPage:CreateFontString(nil, "OVERLAY")
    SetFont(simDesc, "small")
    simDesc:SetPoint("TOPLEFT", simTitle, "BOTTOMLEFT", 0, -6)
    simDesc:SetWidth(520)
    simDesc:SetJustifyH("LEFT")
    simDesc:SetText("Select dungeon and desired chest result.")
    simDesc:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])

    -- NOTE: Avoid OptionsFrameTabButtonTemplate / PanelTemplates_TabResize here.
    -- On some modern clients, it can error because the template's Text region isn't present.
    -- Use simple button-tabs with manual selected styling instead.
    local tab1 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab1:SetSize(110, 22)
    tab1:SetText("Simulator")
    tab1:SetPoint("TOPLEFT", tabsBar, "TOPLEFT", 0, 2)

    local tab2 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab2:SetSize(110, 22)
    tab2:SetText("Planner")
    tab2:SetPoint("LEFT", tab1, "RIGHT", 8, 0)

    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleButton then
            S:HandleButton(tab1)
            S:HandleButton(tab2)
        end
    end

    local function SetTabSelected(btn, selected)
        if not btn then return end
        if selected then
            btn:Disable()
            local fs = btn.GetFontString and btn:GetFontString() or nil
            if fs then fs:SetTextColor(COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3]) end
        else
            btn:Enable()
            local fs = btn.GetFontString and btn:GetFontString() or nil
            if fs then fs:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]) end
        end
    end

    local function SelectTab(tabId)
        if tabId == 2 then
            simPage:Hide()
            plannerPage:Show()
            SetTabSelected(tab2, true)
            SetTabSelected(tab1, false)
        else
            plannerPage:Hide()
            simPage:Show()
            SetTabSelected(tab1, true)
            SetTabSelected(tab2, false)
        end
    end

    tab1:SetScript("OnClick", function() SelectTab(1) end)
    tab2:SetScript("OnClick", function() SelectTab(2) end)

    -- Default tab
    SelectTab(1)

    -- 1. Configuration Panel (Top Row) [Simulator tab]
    local configPanel = CreateFrame("Frame", nil, simPage, "BackdropTemplate")
    configPanel:SetPoint("TOPLEFT", simDesc, "BOTTOMLEFT", 0, -10)
    configPanel:SetPoint("RIGHT", simPage, "RIGHT", 0, 0)
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
    local mapDropdown = CreateFrame("Frame", "TwichUIScoreSimMapDropdown", simPage, "UIDropDownMenuTemplate")
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

    local okStripMap = SafeCall("Strip map dropdown", function()
        StripDropDown(mapDropdown)
    end)

    local okClickMap = SafeCall("Make map dropdown clickable", function()
        MakeDropDownFullClickable(mapDropdown)
    end)

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

        local levelLabel = configPanel:CreateFontString(nil, "OVERLAY")
        SetFont(levelLabel)
        levelLabel:SetPoint("BOTTOM", levelInput, "TOP", 0, 5)
        levelLabel:SetText("Level")
        levelLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    end)

    -- Chest Selection
    local chestDropdown
    SafeCall("Create chest dropdown", function()
        if not levelInput then
            Err("Level input missing; anchoring chest dropdown to map dropdown")
        end

        chestDropdown = CreateFrame("Frame", "TwichUIScoreSimChestDropdown", simPage, "UIDropDownMenuTemplate")
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
    end)
    -- Skinning done inline above

    -- 2. Results Panel (Bottom, Full Width) [Simulator tab]
    local resultsPanel
    SafeCall("Create results panel", function()
        resultsPanel = CreateFrame("Frame", nil, simPage, "BackdropTemplate")
        resultsPanel:SetPoint("TOPLEFT", configPanel, "BOTTOMLEFT", 0, -10)
        resultsPanel:SetPoint("RIGHT", simPage, "RIGHT", 0, 0)
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

    -- 3. Score Planner [Planner tab]
    local plannerPanel
    SafeCall("Create planner panel", function()
        plannerPanel = CreateFrame("Frame", nil, plannerPage, "BackdropTemplate")
        plannerPanel:SetPoint("TOPLEFT", plannerPage, "TOPLEFT", 0, 0)
        plannerPanel:SetPoint("BOTTOMRIGHT", plannerPage, "BOTTOMRIGHT", 0, 0)

        plannerPanel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        plannerPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        plannerPanel:SetBackdropBorderColor(0, 0, 0, 1)
    end)

    local plannerOutput
    local desiredTotalInput
    local plannerMaxLevelInput
    local plannerKeyWeightInput
    local plannerChest2PenaltyInput
    local plannerChest3PenaltyInput
    local plannerChestDropdown
    local plannerPreferLowerKeysCheck
    local plannerPreferLowerChestsCheck

    local function HookTooltip(frame, title, body)
        if not frame or type(frame.SetScript) ~= "function" then return end

        local oldEnter = frame.GetScript and frame:GetScript("OnEnter") or nil
        local oldLeave = frame.GetScript and frame:GetScript("OnLeave") or nil

        frame:SetScript("OnEnter", function(self, ...)
            if type(oldEnter) == "function" then
                pcall(oldEnter, self, ...)
            end
            local gt = _G.GameTooltip
            if not gt then return end
            gt:SetOwner(self, "ANCHOR_RIGHT")
            gt:SetText(tostring(title or ""), 1, 1, 1)
            if body and body ~= "" then
                gt:AddLine(tostring(body), 1, 1, 1, true)
            end
            gt:Show()
        end)

        frame:SetScript("OnLeave", function(self, ...)
            if type(oldLeave) == "function" then
                pcall(oldLeave, self, ...)
            end
            if _G.GameTooltip then
                _G.GameTooltip:Hide()
            end
        end)
    end

    local function ColorWrap(text, r, g, b)
        local rr = math.max(0, math.min(255, math.floor((tonumber(r) or 1) * 255 + 0.5)))
        local gg = math.max(0, math.min(255, math.floor((tonumber(g) or 1) * 255 + 0.5)))
        local bb = math.max(0, math.min(255, math.floor((tonumber(b) or 1) * 255 + 0.5)))
        return string.format("|cff%02x%02x%02x%s|r", rr, gg, bb, tostring(text or ""))
    end

    local function GetPlannerConfig()
        local cfg = {}

        cfg.maxLevel = tonumber(plannerMaxLevelInput and plannerMaxLevelInput:GetText()) or 30
        if cfg.maxLevel < 2 then cfg.maxLevel = 2 end
        if cfg.maxLevel > 40 then cfg.maxLevel = 40 end

        cfg.keyWeight = tonumber(plannerKeyWeightInput and plannerKeyWeightInput:GetText()) or 100
        if cfg.keyWeight < 1 then cfg.keyWeight = 1 end

        cfg.chest2Penalty = tonumber(plannerChest2PenaltyInput and plannerChest2PenaltyInput:GetText()) or 50
        if cfg.chest2Penalty < 0 then cfg.chest2Penalty = 0 end

        cfg.chest3Penalty = tonumber(plannerChest3PenaltyInput and plannerChest3PenaltyInput:GetText()) or 100
        if cfg.chest3Penalty < 0 then cfg.chest3Penalty = 0 end

        cfg.maxChest = tonumber(plannerChestDropdown and plannerChestDropdown.selectedValue) or 3
        if cfg.maxChest ~= 1 and cfg.maxChest ~= 2 and cfg.maxChest ~= 3 then cfg.maxChest = 3 end

        cfg.preferLowerKeys = (plannerPreferLowerKeysCheck and plannerPreferLowerKeysCheck.GetChecked and
            plannerPreferLowerKeysCheck:GetChecked()) == true

        cfg.preferLowerChests = (plannerPreferLowerChestsCheck and plannerPreferLowerChestsCheck.GetChecked and
            plannerPreferLowerChestsCheck:GetChecked()) == true

        return cfg
    end

    local function GetOverallScore()
        local C_ChallengeMode = _G.C_ChallengeMode
        if C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
            return tonumber(C_ChallengeMode.GetOverallDungeonScore())
        end
        return nil
    end

    local function ChestText(chest)
        if chest == 3 then return "+3" end
        if chest == 2 then return "+2" end
        return "+1"
    end

    local function ChestDifficultyPenalty(chest, cfg)
        -- Player-configurable penalties.
        if chest == 1 then return 0 end
        if chest == 2 then return tonumber(cfg and cfg.chest2Penalty) or 50 end
        return tonumber(cfg and cfg.chest3Penalty) or 100
    end

    local function GetTimeSecForChest(mapId, chest)
        local parTime = ScoreCalculator and ScoreCalculator.GetParTimeSeconds and
            ScoreCalculator.GetParTimeSeconds(mapId)
        if not parTime then return nil end
        if chest == 3 then
            return parTime * 0.6 - 1
        elseif chest == 2 then
            return parTime * 0.8 - 1
        end
        return parTime * 0.99
    end

    local function ComputeEasiestPlan(desiredTotal)
        local cfg = GetPlannerConfig()
        desiredTotal = tonumber(desiredTotal)
        if not desiredTotal then
            return nil, "Enter a target total score"
        end

        local overall = GetOverallScore()
        -- Treat missing score as 0 so new characters (or unavailable APIs) don't show an error.
        overall = tonumber(overall) or 0

        local needed = Round0(desiredTotal - overall)
        if needed <= 0 then
            return {
                overall = Round0(overall),
                desired = Round0(desiredTotal),
                needed = needed,
                picks = {},
                totalGain = 0,
                projected = Round0(overall),
            }
        end

        local maxLevel = tonumber(cfg.maxLevel) or 30
        local chestList
        if cfg.maxChest == 1 then
            chestList = { 1 }
        elseif cfg.maxChest == 2 then
            chestList = { 1, 2 }
        else
            chestList = { 1, 2, 3 }
        end

        local maps = GetMapList() or {}
        if #maps == 0 then
            return nil, "No dungeons found"
        end

        local perMapOptions = {}
        for _, map in ipairs(maps) do
            local mapId = map.id
            local mapName = map.name

            local currentScore = 0
            if ScoreCalculator and type(ScoreCalculator.TryGetBlizzardRunScore) == "function" then
                local cs = ScoreCalculator.TryGetBlizzardRunScore(mapId, nil, nil)
                currentScore = Round0(cs or 0)
            end

            -- Keep multiple candidates per gain so preference caps (keys/chests) remain feasible.
            -- Previously we kept only one "best" option per gain which could discard, e.g., +1-only options.
            local bestByGain = {}
            for level = 2, maxLevel do
                for _, chest in ipairs(chestList) do
                    local timeSec = GetTimeSecForChest(mapId, chest)
                    local simScore = nil
                    if ScoreCalculator and type(ScoreCalculator.CalculateForRun) == "function" then
                        local s = ScoreCalculator.CalculateForRun(mapId, level, timeSec)
                        simScore = Round0(s or 0)
                    end

                    local gain = (simScore or 0) - currentScore
                    if gain > 0 then
                        local gainClamped = gain
                        if gainClamped > needed then gainClamped = needed end

                        local difficulty = (level * (tonumber(cfg.keyWeight) or 100)) +
                            ChestDifficultyPenalty(chest, cfg)
                        bestByGain[gainClamped] = bestByGain[gainClamped] or {}
                        local bucket = bestByGain[gainClamped]
                        local existing = bucket[chest]

                        if (not existing)
                            or (difficulty < existing.difficulty)
                            or (difficulty == existing.difficulty and (simScore or 0) > (existing.simScore or 0))
                        then
                            bucket[chest] = {
                                mapId = mapId,
                                mapName = mapName,
                                level = level,
                                chest = chest,
                                timeSec = timeSec,
                                currentScore = currentScore,
                                simScore = simScore,
                                gain = gain,
                                gainClamped = gainClamped,
                                difficulty = difficulty,
                            }
                        end
                    end
                end
            end

            local options = {}
            for _, bucket in pairs(bestByGain) do
                if type(bucket) == "table" then
                    for _, opt in pairs(bucket) do
                        options[#options + 1] = opt
                    end
                end
            end

            if #options > 0 then
                table.sort(options, function(a, b)
                    if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
                    return (a.gain or 0) > (b.gain or 0)
                end)
                perMapOptions[#perMapOptions + 1] = options
            end
        end

        if #perMapOptions == 0 then
            return nil, "No score improvements found"
        end

        local function RunDP(maxKeyCap, maxChestCap)
            local INF = 10 ^ 15
            local dp = {}
            for g = 0, needed do
                dp[g] = INF
            end
            dp[0] = 0

            local prevChoice = {}

            for i, options in ipairs(perMapOptions) do
                local dp2 = {}
                prevChoice[i] = {}

                for g = 0, needed do
                    dp2[g] = dp[g]
                    prevChoice[i][g] = { prev = g, opt = nil }
                end

                for g = 0, needed do
                    local base = dp[g]
                    if base < INF then
                        for _, opt in ipairs(options) do
                            if (not maxKeyCap or (tonumber(opt.level) or 0) <= maxKeyCap)
                                and (not maxChestCap or (tonumber(opt.chest) or 0) <= maxChestCap)
                            then
                                local ng = g + (opt.gainClamped or 0)
                                if ng > needed then ng = needed end
                                local nd = base + (opt.difficulty or 0)
                                if nd < dp2[ng] then
                                    dp2[ng] = nd
                                    prevChoice[i][ng] = { prev = g, opt = opt }
                                end
                            end
                        end
                    end
                end

                dp = dp2
            end

            return dp, prevChoice, INF
        end

        local dp, prevChoice, INF
        local chosenCap = nil
        local chosenChestCap = nil

        local function TrySolveForCaps(keyCap, chestCap)
            local dpc, pre, inf = RunDP(keyCap, chestCap)
            if dpc and dpc[needed] and dpc[needed] < inf then
                dp, prevChoice, INF = dpc, pre, inf
                chosenCap = keyCap
                chosenChestCap = chestCap
                return true
            end
            return false
        end

        if cfg.preferLowerKeys and cfg.preferLowerChests then
            for keyCap = 2, maxLevel do
                for chestCap = 1, (cfg.maxChest or 3) do
                    if TrySolveForCaps(keyCap, chestCap) then
                        break
                    end
                end
                if dp then break end
            end
        elseif cfg.preferLowerKeys then
            for keyCap = 2, maxLevel do
                if TrySolveForCaps(keyCap, nil) then
                    break
                end
            end
        elseif cfg.preferLowerChests then
            for chestCap = 1, (cfg.maxChest or 3) do
                if TrySolveForCaps(nil, chestCap) then
                    break
                end
            end
        end

        if not dp then
            dp, prevChoice, INF = RunDP(nil, nil)
        end

        if not dp or dp[needed] >= INF then
            return nil, "Could not find a plan to reach the target"
        end

        local picks = {}
        local g = needed
        for i = #perMapOptions, 1, -1 do
            local step = prevChoice[i] and prevChoice[i][g]
            if step and step.opt then
                picks[#picks + 1] = step.opt
                g = step.prev or g
            else
                g = step and (step.prev or g) or g
            end
        end

        table.sort(picks, function(a, b)
            return (a.difficulty or 0) < (b.difficulty or 0)
        end)

        local totalGain = 0
        for _, opt in ipairs(picks) do
            totalGain = totalGain + (opt.gain or 0)
        end

        return {
            overall = Round0(overall),
            desired = Round0(desiredTotal),
            needed = needed,
            picks = picks,
            totalGain = Round0(totalGain),
            projected = Round0(overall + totalGain),
            maxKeyCap = chosenCap,
            maxChestCap = chosenChestCap,
        }
    end

    SafeCall("Create planner controls", function()
        if not plannerPanel then return end

        local header = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(header, "large")
        header:SetPoint("TOPLEFT", plannerPanel, "TOPLEFT", 20, -15)
        header:SetText("Mythic+ Score Planner")
        header:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

        local sub = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(sub, "small")
        sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        sub:SetText("Enter a target total score; find the easiest path to reach it.")
        sub:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])

        local inputLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(inputLabel)
        inputLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
        inputLabel:SetText("Target Total")
        inputLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

        desiredTotalInput = CreateFrame("EditBox", nil, plannerPanel, "InputBoxTemplate")
        desiredTotalInput:SetSize(80, 20)
        desiredTotalInput:SetPoint("LEFT", inputLabel, "RIGHT", 12, 0)
        desiredTotalInput:SetAutoFocus(false)
        desiredTotalInput:SetNumeric(true)
        desiredTotalInput:SetJustifyH("CENTER")

        desiredTotalInput:SetText("2000")

        HookTooltip(desiredTotalInput, "Target Total",
            "The overall score you want to reach. The planner chooses a set of dungeon improvements to meet or exceed the needed gain.")

        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleEditBox then S:HandleEditBox(desiredTotalInput) end
        end

        local findButton = CreateFrame("Button", nil, plannerPanel, "UIPanelButtonTemplate")
        findButton:SetSize(140, 22)
        findButton:SetPoint("LEFT", desiredTotalInput, "RIGHT", 12, 0)
        findButton:SetText("Find Easiest Path")
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleButton then S:HandleButton(findButton) end
        end

        -- Config row
        local cfgLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(cfgLabel, "small")
        cfgLabel:SetPoint("TOPLEFT", inputLabel, "BOTTOMLEFT", 0, -18)
        cfgLabel:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
        cfgLabel:SetText("Options")

        local maxLevelLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(maxLevelLabel, "small")
        maxLevelLabel:SetPoint("LEFT", cfgLabel, "RIGHT", 12, 0)
        maxLevelLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
        maxLevelLabel:SetText("Max Key")

        plannerMaxLevelInput = CreateFrame("EditBox", nil, plannerPanel, "InputBoxTemplate")
        plannerMaxLevelInput:SetSize(40, 20)
        plannerMaxLevelInput:SetPoint("LEFT", maxLevelLabel, "RIGHT", 6, 0)
        plannerMaxLevelInput:SetAutoFocus(false)
        plannerMaxLevelInput:SetNumeric(true)
        plannerMaxLevelInput:SetJustifyH("CENTER")
        plannerMaxLevelInput:SetText("12")
        HookTooltip(plannerMaxLevelInput, "Max Key",
            "Limits the recommended key level. Higher values allow bigger score jumps but may increase the suggested max key.")
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleEditBox then S:HandleEditBox(plannerMaxLevelInput) end
        end

        local chestLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(chestLabel, "small")
        chestLabel:SetPoint("LEFT", plannerMaxLevelInput, "RIGHT", 12, 0)
        chestLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
        chestLabel:SetText("Chests")

        plannerChestDropdown = CreateFrame("Frame", "TwichUIScorePlannerChestDropdown", plannerPanel,
            "UIDropDownMenuTemplate")
        plannerChestDropdown:SetPoint("LEFT", chestLabel, "RIGHT", 4, -2)
        plannerChestDropdown:SetFrameLevel((plannerPanel:GetFrameLevel() or 0) + 50)
        if type(_G.UIDropDownMenu_SetWidth) == "function" then _G.UIDropDownMenu_SetWidth(plannerChestDropdown, 90) end
        if type(_G.UIDropDownMenu_SetText) == "function" then _G.UIDropDownMenu_SetText(plannerChestDropdown, "+1/+2/+3") end
        if type(_G.UIDropDownMenu_JustifyText) == "function" then
            _G.UIDropDownMenu_JustifyText(plannerChestDropdown,
                "LEFT")
        end
        plannerChestDropdown.selectedValue = 3
        HookTooltip(plannerChestDropdown, "Chests",
            "Restricts which chest tiers the planner is allowed to recommend (e.g. +1 only, +1/+2, or +1/+2/+3).")
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleDropDownBox then S:HandleDropDownBox(plannerChestDropdown) end
        end
        StripDropDown(plannerChestDropdown)
        MakeDropDownFullClickable(plannerChestDropdown)

        -- Preferences row (separate from the main options row)
        local prefLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(prefLabel, "small")
        prefLabel:SetPoint("TOPLEFT", cfgLabel, "BOTTOMLEFT", 0, -18)
        prefLabel:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
        prefLabel:SetText("Preferences")

        plannerPreferLowerKeysCheck = CreateFrame("CheckButton", nil, plannerPanel, "ChatConfigCheckButtonTemplate")
        plannerPreferLowerKeysCheck:SetPoint("LEFT", prefLabel, "RIGHT", 12, 0)
        plannerPreferLowerKeysCheck:SetChecked(false)
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleCheckBox then S:HandleCheckBox(plannerPreferLowerKeysCheck) end
        end
        HookTooltip(plannerPreferLowerKeysCheck, "Prefer lower keys",
            "When enabled, the planner minimizes the highest recommended key level (may suggest more runs).")

        local preferKeysLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(preferKeysLabel, "small")
        preferKeysLabel:SetPoint("LEFT", plannerPreferLowerKeysCheck, "RIGHT", 2, 0)
        preferKeysLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
        preferKeysLabel:SetText("Prefer lower keys")

        plannerPreferLowerChestsCheck = CreateFrame("CheckButton", nil, plannerPanel, "ChatConfigCheckButtonTemplate")
        plannerPreferLowerChestsCheck:SetPoint("LEFT", preferKeysLabel, "RIGHT", 14, 0)
        plannerPreferLowerChestsCheck:SetChecked(false)
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleCheckBox then S:HandleCheckBox(plannerPreferLowerChestsCheck) end
        end
        HookTooltip(plannerPreferLowerChestsCheck, "Prefer lower chests",
            "When enabled, the planner minimizes the highest chest tier it recommends (prefers +1, then +2, then +3), even if it suggests more runs.")

        local preferChestsLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(preferChestsLabel, "small")
        preferChestsLabel:SetPoint("LEFT", plannerPreferLowerChestsCheck, "RIGHT", 2, 0)
        preferChestsLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
        preferChestsLabel:SetText("Prefer lower chests")

        SafeCall("Init planner chest dropdown", function()
            local ddInit = _G.UIDropDownMenu_Initialize
            local ddCreateInfo = _G.UIDropDownMenu_CreateInfo
            local ddAddButton = _G.UIDropDownMenu_AddButton
            local ddSetSelectedValue = _G.UIDropDownMenu_SetSelectedValue
            local ddSetText = _G.UIDropDownMenu_SetText
            if type(ddInit) ~= "function" or type(ddCreateInfo) ~= "function" or type(ddAddButton) ~= "function" then return end

            local options = {
                { value = 1, text = "+1 only" },
                { value = 2, text = "+1/+2" },
                { value = 3, text = "+1/+2/+3" },
            }

            ddInit(plannerChestDropdown, function(self, level)
                level = level or 1
                for _, opt in ipairs(options) do
                    local info = ddCreateInfo()
                    info.text = opt.text
                    info.arg1 = opt.value
                    info.arg2 = opt.text
                    info.func = function(_, arg1, arg2)
                        plannerChestDropdown.selectedValue = arg1
                        if type(ddSetSelectedValue) == "function" then ddSetSelectedValue(plannerChestDropdown, arg1) end
                        if type(ddSetText) == "function" then ddSetText(plannerChestDropdown, arg2) end
                    end
                    ddAddButton(info, level)
                end
            end)
        end)

        local weightLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(weightLabel, "small")
        weightLabel:SetPoint("TOPLEFT", prefLabel, "BOTTOMLEFT", 0, -18)
        weightLabel:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
        weightLabel:SetText("Difficulty Weights")

        local keyWLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(keyWLabel, "small")
        keyWLabel:SetPoint("LEFT", weightLabel, "RIGHT", 12, 0)
        keyWLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
        keyWLabel:SetText("Key")

        plannerKeyWeightInput = CreateFrame("EditBox", nil, plannerPanel, "InputBoxTemplate")
        plannerKeyWeightInput:SetSize(45, 20)
        plannerKeyWeightInput:SetPoint("LEFT", keyWLabel, "RIGHT", 6, 0)
        plannerKeyWeightInput:SetAutoFocus(false)
        plannerKeyWeightInput:SetNumeric(true)
        plannerKeyWeightInput:SetJustifyH("CENTER")
        plannerKeyWeightInput:SetText("100")
        HookTooltip(plannerKeyWeightInput, "Key weight",
            "Controls how strongly the planner penalizes higher key levels. Higher values make the 'easiest' plan favor lower keys more aggressively.")
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleEditBox then S:HandleEditBox(plannerKeyWeightInput) end
        end

        local c2Label = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(c2Label, "small")
        c2Label:SetPoint("LEFT", plannerKeyWeightInput, "RIGHT", 12, 0)
        c2Label:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
        c2Label:SetText("+2")

        plannerChest2PenaltyInput = CreateFrame("EditBox", nil, plannerPanel, "InputBoxTemplate")
        plannerChest2PenaltyInput:SetSize(45, 20)
        plannerChest2PenaltyInput:SetPoint("LEFT", c2Label, "RIGHT", 6, 0)
        plannerChest2PenaltyInput:SetAutoFocus(false)
        plannerChest2PenaltyInput:SetNumeric(true)
        plannerChest2PenaltyInput:SetJustifyH("CENTER")
        plannerChest2PenaltyInput:SetText("50")
        HookTooltip(plannerChest2PenaltyInput, "+2 penalty",
            "Adds difficulty cost when recommending a +2 chest (faster time). Higher values make the planner avoid +2 unless it helps reach the target.")
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleEditBox then S:HandleEditBox(plannerChest2PenaltyInput) end
        end

        local c3Label = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(c3Label, "small")
        c3Label:SetPoint("LEFT", plannerChest2PenaltyInput, "RIGHT", 12, 0)
        c3Label:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
        c3Label:SetText("+3")

        plannerChest3PenaltyInput = CreateFrame("EditBox", nil, plannerPanel, "InputBoxTemplate")
        plannerChest3PenaltyInput:SetSize(45, 20)
        plannerChest3PenaltyInput:SetPoint("LEFT", c3Label, "RIGHT", 6, 0)
        plannerChest3PenaltyInput:SetAutoFocus(false)
        plannerChest3PenaltyInput:SetNumeric(true)
        plannerChest3PenaltyInput:SetJustifyH("CENTER")
        plannerChest3PenaltyInput:SetText("100")
        HookTooltip(plannerChest3PenaltyInput, "+3 penalty",
            "Adds difficulty cost when recommending a +3 chest (even faster time). Higher values make the planner strongly avoid +3 recommendations.")
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleEditBox then S:HandleEditBox(plannerChest3PenaltyInput) end
        end

        -- Separator between configuration and results
        local plannerSep = plannerPanel:CreateTexture(nil, "ARTWORK")
        plannerSep:SetColorTexture(1, 1, 1, 0.10)
        plannerSep:SetHeight(1)
        plannerSep:SetPoint("LEFT", plannerPanel, "LEFT", 20, 0)
        plannerSep:SetPoint("RIGHT", plannerPanel, "RIGHT", -20, 0)
        plannerSep:SetPoint("TOP", plannerChest3PenaltyInput, "BOTTOM", 0, -16)

        local resultsLabel = plannerPanel:CreateFontString(nil, "OVERLAY")
        SetFont(resultsLabel, "large")
        resultsLabel:SetPoint("TOPLEFT", plannerSep, "BOTTOMLEFT", 0, -10)
        resultsLabel:SetText("Results")
        resultsLabel:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

        -- Scrollable output area
        local scroll = CreateFrame("ScrollFrame", nil, plannerPanel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", resultsLabel, "BOTTOMLEFT", 0, -10)
        scroll:SetPoint("BOTTOMRIGHT", plannerPanel, "BOTTOMRIGHT", -28, 12)

        -- ElvUI skin for scrollbar
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleScrollBar and scroll.ScrollBar then
                S:HandleScrollBar(scroll.ScrollBar)
            end
        end

        local scrollChild = CreateFrame("Frame", nil, scroll)
        scrollChild:SetPoint("TOPLEFT")
        scrollChild:SetSize(1, 1)
        scroll:SetScrollChild(scrollChild)

        -- Table-like output
        local summaryText = scrollChild:CreateFontString(nil, "OVERLAY")
        SetFont(summaryText, "normal")
        summaryText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        summaryText:SetJustifyH("LEFT")
        summaryText:SetTextColor(0.85, 0.85, 0.85)
        summaryText:SetWidth(520)
        summaryText:SetText("")

        local tableHeader = CreateFrame("Frame", nil, scrollChild)
        tableHeader:SetPoint("TOPLEFT", summaryText, "BOTTOMLEFT", 0, -12)
        tableHeader:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        tableHeader:SetHeight(18)

        local hdrDungeon = tableHeader:CreateFontString(nil, "OVERLAY")
        SetFont(hdrDungeon, "small")
        hdrDungeon:SetPoint("LEFT", tableHeader, "LEFT", 0, 0)
        hdrDungeon:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
        hdrDungeon:SetText("Dungeon")

        local hdrKey = tableHeader:CreateFontString(nil, "OVERLAY")
        SetFont(hdrKey, "small")
        hdrKey:SetPoint("LEFT", tableHeader, "LEFT", 250, 0)
        hdrKey:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
        hdrKey:SetText("Key")

        local hdrChest = tableHeader:CreateFontString(nil, "OVERLAY")
        SetFont(hdrChest, "small")
        hdrChest:SetPoint("LEFT", tableHeader, "LEFT", 310, 0)
        hdrChest:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
        hdrChest:SetText("Chest / Time")

        local hdrGain = tableHeader:CreateFontString(nil, "OVERLAY")
        SetFont(hdrGain, "small")
        hdrGain:SetPoint("RIGHT", tableHeader, "RIGHT", 0, 0)
        hdrGain:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
        hdrGain:SetText("Gain")

        local headerSep = scrollChild:CreateTexture(nil, "ARTWORK")
        headerSep:SetColorTexture(1, 1, 1, 0.10)
        headerSep:SetHeight(1)
        headerSep:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, -4)
        headerSep:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

        local plannerRows = {}
        local MAX_ROWS = 30

        local function NavigateToDungeon(mapId)
            mapId = tonumber(mapId)
            if not mapId then return end
            if not MythicPlusModule or not MythicPlusModule.MainWindow then return end

            local mainWindow = MythicPlusModule.MainWindow
            local enable = mainWindow and mainWindow.Enable
            if type(enable) == "function" then
                enable(mainWindow, false)
            end

            local showPanel = mainWindow and mainWindow.ShowPanel
            if type(showPanel) == "function" then
                showPanel(mainWindow, "dungeons")
            end

            local function ApplySelection()
                local getPanelFrame = mainWindow and mainWindow.GetPanelFrame
                local panel = (type(getPanelFrame) == "function") and getPanelFrame(mainWindow, "dungeons")
                if panel then
                    ---@cast panel TwichUI_MythicPlus_DungeonsPanel
                    panel.__twichuiSelectedMapId = mapId
                end
                if MythicPlusModule.Dungeons and type(MythicPlusModule.Dungeons.Refresh) == "function" then
                    MythicPlusModule.Dungeons:Refresh()
                end
            end

            local C_Timer = _G.C_Timer
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, ApplySelection)
            else
                ApplySelection()
            end
        end

        local function EnsureRow(i)
            if plannerRows[i] then return plannerRows[i] end

            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(18)
            row:EnableMouse(true)

            local hover = row:CreateTexture(nil, "BACKGROUND")
            hover:SetAllPoints(row)
            if E and E.media and E.media.bordercolor then
                local r, g, b = unpack(E.media.bordercolor)
                hover:SetColorTexture(r or 1, g or 1, b or 1, 0.10)
            else
                hover:SetColorTexture(1, 1, 1, 0.10)
            end
            hover:Hide()
            row.__twichuiHoverBG = hover

            row:SetScript("OnMouseUp", function(self)
                if self.__twichuiMapId then
                    NavigateToDungeon(self.__twichuiMapId)
                end
            end)

            row:SetScript("OnEnter", function(self)
                if self.__twichuiHoverBG then
                    self.__twichuiHoverBG:Show()
                end

                local gt = _G.GameTooltip
                if not gt then return end
                gt:SetOwner(self, "ANCHOR_RIGHT")
                gt:SetText("Navigate to dungeon", 1, 1, 1)
                gt:AddLine("Click to open the Dungeons panel for this dungeon.", 1, 1, 1, true)
                gt:Show()
            end)

            row:SetScript("OnLeave", function(self)
                if self.__twichuiHoverBG then
                    self.__twichuiHoverBG:Hide()
                end
                if _G.GameTooltip then
                    _G.GameTooltip:Hide()
                end
            end)

            if i == 1 then
                row:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", 0, -8)
            else
                row:SetPoint("TOPLEFT", plannerRows[i - 1], "BOTTOMLEFT", 0, -6)
            end
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

            row.dungeon = row:CreateFontString(nil, "OVERLAY")
            SetFont(row.dungeon, "normal")
            row.dungeon:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.dungeon:SetWidth(240)
            row.dungeon:SetJustifyH("LEFT")

            row.key = row:CreateFontString(nil, "OVERLAY")
            SetFont(row.key, "normal")
            row.key:SetPoint("LEFT", row, "LEFT", 250, 0)
            row.key:SetWidth(55)
            row.key:SetJustifyH("LEFT")

            row.chestTime = row:CreateFontString(nil, "OVERLAY")
            SetFont(row.chestTime, "small")
            row.chestTime:SetPoint("LEFT", row, "LEFT", 310, 0)
            row.chestTime:SetWidth(165)
            row.chestTime:SetJustifyH("LEFT")

            row.gain = row:CreateFontString(nil, "OVERLAY")
            SetFont(row.gain, "normal")
            row.gain:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.gain:SetJustifyH("RIGHT")

            row:Hide()
            plannerRows[i] = row
            return row
        end

        local function ClearRows()
            for i = 1, MAX_ROWS do
                if plannerRows[i] then
                    plannerRows[i]:Hide()
                end
            end
        end

        local function SetScrollHeight(lastWidget)
            local bottom = lastWidget or headerSep
            local h = 0
            if bottom and bottom.GetBottom and scrollChild.GetTop then
                local top = scrollChild:GetTop() or 0
                local bot = bottom:GetBottom() or 0
                h = (top - bot) + 20
            end
            if h < 1 then h = 1 end
            scrollChild:SetSize(520, h)
        end

        local function RenderPlannerPlan(plan, err)
            if not summaryText then return end
            if not plan then
                summaryText:SetText(ColorWrap(tostring(err or "Unknown error"), 1, 0.25, 0.25))
                tableHeader:Hide()
                headerSep:Hide()
                ClearRows()
                SetScrollHeight(summaryText)
                return
            end

            if plan.needed and plan.needed <= 0 then
                summaryText:SetText(
                    ColorWrap("Current Total: ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                    .. ColorWrap(tostring(plan.overall), COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3])
                    .. "\n"
                    .. ColorWrap("Target Total: ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                    .. ColorWrap(tostring(plan.desired), COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
                    .. "\n"
                    .. ColorWrap("You are already at or above the target.", COLOR_MUTED[1], COLOR_MUTED[2],
                        COLOR_MUTED[3])
                )
                tableHeader:Hide()
                headerSep:Hide()
                ClearRows()
                SetScrollHeight(summaryText)
                return
            end

            tableHeader:Show()
            headerSep:Show()
            ClearRows()

            local sumGain = 0
            for _, opt in ipairs(plan.picks or {}) do
                sumGain = sumGain + (opt.gain or 0)
            end

            summaryText:SetText(
                ColorWrap("Current Total: ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                .. ColorWrap(tostring(plan.overall), COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3])
                .. "    "
                .. ColorWrap("Target: ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                .. ColorWrap(tostring(plan.desired), COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
                .. "    "
                .. ColorWrap("Need ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                .. ColorWrap("+" .. tostring(plan.needed), 0, 1, 0)
                .. "\n"
                .. ColorWrap("Planned Gain: ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                .. ColorWrap("+" .. tostring(Round0(sumGain)), 0, 1, 0)
                .. ColorWrap("   Projected Total: ", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
                .. ColorWrap(tostring(Round0(plan.overall + sumGain)), COLOR_ACCENT[1], COLOR_ACCENT[2],
                    COLOR_ACCENT[3])
            )

            local lastRow = headerSep
            for i, opt in ipairs(plan.picks or {}) do
                if i > MAX_ROWS then break end
                local row = EnsureRow(i)
                local dungeonName = tostring(opt.mapName or opt.mapId)
                local levelText = "+" .. tostring(tonumber(opt.level) or 0)
                local t = opt.timeSec and FormatTime(opt.timeSec) or "N/A"
                local chestTimeText = string.format("(%s, %s)", ChestText(opt.chest), t)
                local gain = Round0(opt.gain or 0)

                local chestColor = CHEST_TIME_COLORS[tonumber(opt.chest or 0)]
                local cr, cg, cb = COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]
                if chestColor then
                    cr, cg, cb = chestColor[1], chestColor[2], chestColor[3]
                end

                row.dungeon:SetText(ColorWrap(dungeonName, COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
                row.key:SetText(ColorWrap(levelText, COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3]))
                row.chestTime:SetText(ColorWrap(chestTimeText, cr, cg, cb))
                row.gain:SetText(ColorWrap("+" .. tostring(gain), 0, 1, 0))

                row.__twichuiMapId = opt.mapId

                row:Show()
                lastRow = row
            end

            SetScrollHeight(lastRow)
        end

        -- Restore last results from saved variables (no recompute) until the player clicks Find again.
        do
            local cached = LoadScorePlannerLastPlan()
            if cached and type(cached) == "table" then
                RenderPlannerPlan(cached)
            end
        end

        findButton:SetScript("OnClick", function()
            SafeCall("Compute planner path", function()
                if not desiredTotalInput then return end
                local plan, err = ComputeEasiestPlan(desiredTotalInput:GetText())
                if plan then
                    SaveScorePlannerLastPlan(plan)
                end
                RenderPlannerPlan(plan, err)
            end)
        end)
    end)

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
                    iconSize = { 24, 32 },
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
