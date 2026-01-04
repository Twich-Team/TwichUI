local T = unpack(Twich)
local _G = _G

local CreateFrame = _G.CreateFrame

---@type MythicPlusModule
local MP = T:GetModule("MythicPlus")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")
---@type LoggerModule
local Logger = T:GetModule("Logger")

local function NormalizeHexColor(hex)
    if type(hex) ~= "string" or hex == "" then return nil end
    hex = hex:gsub("^|c", ""):gsub("^#", "")
    if #hex == 6 then
        hex = "ff" .. hex
    end
    if #hex ~= 8 then return nil end
    return hex
end

local function GetItemRarityHex(itemLink)
    if not itemLink then return nil end

    local quality
    local itemID = GetItemInfoInstant(itemLink)
    if itemID and _G.C_Item and _G.C_Item.GetItemQualityByID then
        quality = _G.C_Item.GetItemQualityByID(itemID)
    end
    if quality == nil then
        local _, _, q = GetItemInfo(itemLink)
        quality = q
    end
    if quality == nil then return nil end

    local _, _, _, hex = GetItemQualityColor(quality)
    return NormalizeHexColor(hex)
end

local function ColorizeWithHex(hex, text)
    if type(text) ~= "string" then
        text = tostring(text or "")
    end
    hex = NormalizeHexColor(hex)
    if not hex then
        return text
    end
    return "|c" .. hex .. text .. "|r"
end

local function RestoreLoggerInfoColor(text)
    text = tostring(text or "")

    local infoHex = Logger and Logger.LEVELS and Logger.LEVELS.INFO and Logger.LEVELS.INFO.hexColor
    infoHex = NormalizeHexColor(infoHex)
    if not infoHex then
        return text
    end

    -- Logger.Info wraps the full message, but embedded item links and colored segments include "|r",
    -- which would otherwise reset the remaining text back to default chat color.
    return text:gsub("|r", "|r|c" .. infoHex)
end

local function FormatBiSChatMessage(kind, itemLink, receivedILvl, previousILvl, quantity)
    local label
    if kind == "UPGRADE" then
        label = "BiS Upgrade"
    elseif kind == "NEW" then
        label = "BiS Acquired"
    elseif kind == "ROLL" then
        label = "BiS Available (Roll)"
    elseif kind == "VAULT" then
        label = "BiS Available (Great Vault)"
    else
        label = "BiS Found"
    end

    local qty = tonumber(quantity) or 1
    if qty < 1 then qty = 1 end

    local itemText = tostring(itemLink or "")
    if qty > 1 then
        itemText = itemText .. string.format(" x%d", qty)
    end

    local ilvlText = ""
    local r = tonumber(receivedILvl)
    local p = tonumber(previousILvl)

    local hex = GetItemRarityHex(itemLink)
    local function Ilvl(n)
        return ColorizeWithHex(hex, tostring(n))
    end
    if r and p and r > 0 and p > 0 then
        ilvlText = string.format(" (iLvl %s -> %s)", Ilvl(p), Ilvl(r))
    elseif r and r > 0 then
        ilvlText = string.format(" (iLvl %s)", Ilvl(r))
    end

    return string.format("%s: %s%s", label, itemText, ilvlText)
end

--- @class BestInSlotNotificationHandler
--- @field enabled boolean
--- @field frame Frame|nil
local NIH = MP.BestInSlotNotificationHandler or {}
MP.BestInSlotNotificationHandler = NIH

local KEY_PREFIX = "mythicplus.bestInSlot.notifications."

-- Keys for mapping GetItemInfo() returns into a table
local ITEMINFO_KEYS = {
    "name", "link", "quality", "iLevel", "minLevel", "type", "subType",
    "maxStack", "equipLoc", "icon", "sellPrice", "classID", "subClassID",
    "bindType", "expansionID", "setID", "isCraftingReagent"
}

---@param item string|number
---@param callback fun(info:table|nil)|nil
---@return table|nil
local function GetItemInfoTable(item, callback)
    local results = { GetItemInfo(item) }
    if not results[1] then
        if type(callback) == "function" then
            local itemID
            if type(item) == "number" then
                itemID = item
            elseif type(item) == "string" then
                itemID = tonumber(item:match("item:(%d+):"))
            end

            local waiter = CreateFrame("Frame")
            local function OnGetItemInfoReceived(_, _, gotItemID, success)
                if not success then
                    waiter:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                    waiter:SetScript("OnEvent", nil)
                    callback(nil)
                    return
                end

                if not itemID or tonumber(gotItemID) == tonumber(itemID) then
                    waiter:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                    waiter:SetScript("OnEvent", nil)
                    local filled = GetItemInfoTable(item, nil)
                    callback(filled)
                end
            end

            waiter:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            waiter:SetScript("OnEvent", OnGetItemInfoReceived)
        end
        return nil
    end

    local t = {}
    for i = 1, #results do
        t[ITEMINFO_KEYS[i] or ("field" .. i)] = results[i]
    end
    return t
end

local LOOT_SELF_PATTERN = string.gsub(LOOT_ITEM_SELF, "%%s", "(.+)")

local function GetCharacterDB()
    if not MP.Database or not MP.Database.GetForCurrentCharacter then return nil end
    local entry = MP.Database:GetForCurrentCharacter()
    if not entry then return nil end
    if not entry.BestInSlot then entry.BestInSlot = {} end
    return entry.BestInSlot
end

local function GetSelectedBiSItemIDs()
    local db = GetCharacterDB()
    if type(db) ~= "table" then return {} end

    local set = {}
    for k, v in pairs(db) do
        if tonumber(k) then
            local link = (type(v) == "table" and v.link) or v
            if link then
                local itemID = GetItemInfoInstant(link)
                if itemID then
                    set[tonumber(itemID)] = true
                end
            end
        end
    end
    return set
end

local function GetOwnedTable(db)
    if type(db) ~= "table" then return nil end
    db.__ownedBiS = db.__ownedBiS or {}
    return db.__ownedBiS
end

local function GetEffectiveItemLevel(itemLink, fallback)
    if not itemLink then return tonumber(fallback) end
    local effective = GetDetailedItemLevelInfo(itemLink)
    if effective and tonumber(effective) then
        return tonumber(effective)
    end
    return tonumber(fallback)
end

local function WithTemporaryProfileSetting(key, tempValue, fn)
    if type(fn) ~= "function" then return end
    local previous = CM:GetProfileSettingSafe(key, nil)
    CM:SetProfileSettingSafe(key, tempValue)
    local ok, err = pcall(fn)
    CM:SetProfileSettingSafe(key, previous)
    if not ok then
        Logger.Error(tostring(err))
    end
end

local function WithTemporaryBiSSelection(itemLink, fn)
    if type(fn) ~= "function" then return end

    local db = GetCharacterDB()
    if type(db) ~= "table" then
        fn()
        return
    end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then
        fn()
        return
    end

    local key = tonumber(itemID)
    if not key then
        fn()
        return
    end
    local previous = db[key]
    db[key] = { link = itemLink }

    local ok, err = pcall(fn)

    if previous == nil then
        db[key] = nil
    else
        db[key] = previous
    end

    if not ok then
        Logger.Error(tostring(err))
    end
end

local function PlayNotificationSound(settingSuffix, defaultSoundKey)
    local soundKey = CM:GetProfileSettingSafe(KEY_PREFIX .. settingSuffix, defaultSoundKey)
    if soundKey and soundKey ~= "None" then
        local LSM = T.Libs and T.Libs.LSM
        local path = LSM and LSM:Fetch("sound", soundKey)
        if path then
            PlaySoundFile(path, "Master")
        end
    end
end

local function ShowAndLog(kind, itemLink, receivedILvl, previousILvl, quantity)
    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.Initialize then
        MP.BestInSlotNotificationFrame:Initialize()
    end

    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.ShowNotification then
        MP.BestInSlotNotificationFrame:ShowNotification(itemLink, kind, receivedILvl, previousILvl, quantity)
    end

    Logger.Info(RestoreLoggerInfoColor(FormatBiSChatMessage(kind, itemLink, receivedILvl, previousILvl, quantity)))
end

local function ProcessLootItem(itemLink, quantity, overrideILvl)
    if not itemLink then return end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return end

    local selected = GetSelectedBiSItemIDs()
    if not selected[tonumber(itemID)] then
        return
    end

    local db = GetCharacterDB()
    local owned = GetOwnedTable(db)
    if not owned then return end

    local currentILvl = GetEffectiveItemLevel(itemLink, nil)
    if overrideILvl and tonumber(overrideILvl) and tonumber(overrideILvl) > 0 then
        currentILvl = tonumber(overrideILvl)
    end

    local prevILvl = owned[tonumber(itemID)]

    local shouldShow = false
    local kind = "FOUND"

    if not prevILvl then
        shouldShow = true
        kind = "NEW"
    elseif currentILvl and tonumber(prevILvl) and currentILvl > tonumber(prevILvl) then
        shouldShow = true
        kind = "UPGRADE"
    end

    if currentILvl and (not prevILvl or currentILvl > (tonumber(prevILvl) or 0)) then
        owned[tonumber(itemID)] = currentILvl
    elseif not prevILvl then
        owned[tonumber(itemID)] = currentILvl or 0
    end

    if not shouldShow then
        return
    end

    PlayNotificationSound("notificationSound", "TwichUI Green Dude Gets Loot")
    ShowAndLog(kind, itemLink, currentILvl, tonumber(prevILvl), quantity)
end

local function OnStartLootRoll(rollID)
    if not rollID then return end
    if not CM:GetProfileSettingSafe(KEY_PREFIX .. "availabilityRollEnabled", true) then
        return
    end

    NIH.__rollNotified = NIH.__rollNotified or {}
    if NIH.__rollNotified[tonumber(rollID)] then
        return
    end

    local link = _G.GetLootRollItemLink and _G.GetLootRollItemLink(rollID)
    if type(link) ~= "string" or link == "" then
        return
    end

    local itemID = GetItemInfoInstant(link)
    if not itemID then return end
    local selected = GetSelectedBiSItemIDs()
    if not selected[tonumber(itemID)] then
        return
    end

    NIH.__rollNotified[tonumber(rollID)] = true

    local count = 1
    if _G.GetLootRollItemInfo then
        local _, _, c = _G.GetLootRollItemInfo(rollID)
        count = tonumber(c) or 1
        if count < 1 then count = 1 end
    end

    local ilvl = GetEffectiveItemLevel(link, nil)

    PlayNotificationSound("availabilityRollSound", "TwichUI Notification 8")
    ShowAndLog("ROLL", link, ilvl, nil, count)
end

local __lastVaultCheckAt = 0
local function CheckGreatVaultForBiS()
    if not CM:GetProfileSettingSafe(KEY_PREFIX .. "availabilityVaultEnabled", true) then
        return
    end

    local now = (_G.GetTime and _G.GetTime()) or 0
    if now > 0 and (now - __lastVaultCheckAt) < 5 then
        return
    end
    __lastVaultCheckAt = now

    local C_WeeklyRewards = _G.C_WeeklyRewards
    if not C_WeeklyRewards or type(C_WeeklyRewards.GetActivities) ~= "function" then
        return
    end

    -- Only alert when the vault is actually available for selection, when possible.
    if type(C_WeeklyRewards.HasAvailableRewards) == "function" then
        local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
        if ok and not has then
            return
        end
    end

    if type(C_WeeklyRewards.RequestRewards) == "function" then
        pcall(C_WeeklyRewards.RequestRewards)
    end
    if type(C_WeeklyRewards.RequestActivities) == "function" then
        pcall(C_WeeklyRewards.RequestActivities)
    end

    local function TryActivities(...)
        local ok, res = pcall(C_WeeklyRewards.GetActivities, ...)
        if ok and type(res) == "table" then
            return res
        end
        return nil
    end

    local best
    local function Consider(t)
        if type(t) ~= "table" then return end
        if not best or #t > #best then
            best = t
        end
    end

    Consider(TryActivities())
    -- Some clients require an eventTypeId; try the most common one too.
    Consider(TryActivities(1))

    local activities = best
    if type(activities) ~= "table" then
        return
    end

    if type(C_WeeklyRewards.GetActivityItemRewards) ~= "function" then
        return
    end

    NIH.__vaultNotified = NIH.__vaultNotified or {}

    local selected = GetSelectedBiSItemIDs()

    local function GetActivityId(entry)
        if type(entry) == "table" then
            return tonumber(entry.id or entry.activityID or entry.activityId)
        end
        return tonumber(entry)
    end

    for _, entry in ipairs(activities) do
        local activityID = GetActivityId(entry)
        if activityID then
            local ok2, rewards = pcall(C_WeeklyRewards.GetActivityItemRewards, activityID)
            if ok2 and type(rewards) == "table" then
                for _, r in ipairs(rewards) do
                    local link
                    if type(r) == "string" then
                        link = r
                    elseif type(r) == "table" then
                        link = r.itemLink or r.hyperlink or r.link
                    end
                    if type(link) == "string" and link ~= "" then
                        local itemID = GetItemInfoInstant(link)
                        if itemID and selected[tonumber(itemID)] and not NIH.__vaultNotified[tonumber(itemID)] then
                            NIH.__vaultNotified[tonumber(itemID)] = true
                            local ilvl = GetEffectiveItemLevel(link, nil)
                            PlayNotificationSound("availabilityVaultSound", "TwichUI Notification 8")
                            ShowAndLog("VAULT", link, ilvl, nil, 1)
                        end
                    end
                end
            end
        end
    end
end

-- Great Vault UI highlight: animated pixel glow around BiS rewards when the vault window is open.
local function CreatePixelGlow(parent)
    if not parent or not parent.CreateTexture then return nil end

    local ElvUI = rawget(_G, "ElvUI")
    local E = ElvUI and ElvUI[1]
    local borderTexture = (E and E.media and (E.media.blankTex or E.media.normTex)) or "Interface\\Buttons\\WHITE8X8"

    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 20)

    local thickness = 2
    local offset = 2

    local function NewEdge()
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(borderTexture)
        t:SetBlendMode("ADD")
        return t
    end

    f.top = NewEdge()
    f.bottom = NewEdge()
    f.left = NewEdge()
    f.right = NewEdge()

    f.top:SetPoint("TOPLEFT", parent, "TOPLEFT", -offset, offset)
    f.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", offset, offset)
    f.top:SetHeight(thickness)

    f.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -offset, -offset)
    f.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", offset, -offset)
    f.bottom:SetHeight(thickness)

    f.left:SetPoint("TOPLEFT", parent, "TOPLEFT", -offset, offset)
    f.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -offset, -offset)
    f.left:SetWidth(thickness)

    f.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", offset, offset)
    f.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", offset, -offset)
    f.right:SetWidth(thickness)

    f.anim = f:CreateAnimationGroup()
    f.anim:SetLooping("BOUNCE")
    local a = f.anim:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15)
    a:SetToAlpha(1.0)
    a:SetDuration(0.85)
    a:SetSmoothing("IN_OUT")

    return f
end

local VaultHighlight = {
    hooked = false,
    glowByTarget = setmetatable({}, { __mode = "k" }),
    active = setmetatable({}, { __mode = "k" }),
    listener = nil,
}

local function SetGlowColor(glow, r, g, b, a)
    if not glow then return end
    if glow.top then glow.top:SetVertexColor(r, g, b, a) end
    if glow.bottom then glow.bottom:SetVertexColor(r, g, b, a) end
    if glow.left then glow.left:SetVertexColor(r, g, b, a) end
    if glow.right then glow.right:SetVertexColor(r, g, b, a) end
end

local function GetAvailabilityColor()
    local c = CM:GetProfileSettingSafe(KEY_PREFIX .. "frameBorderColorAvailable", { r = 0.23, g = 0.62, b = 1.00, a = 1 })
    return tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1, tonumber(c.a) or 1
end

local function GetCandidateItemID(frame)
    if not frame then return nil end
    if frame.itemID and tonumber(frame.itemID) then
        return tonumber(frame.itemID)
    end

    local link = frame.itemLink or frame.hyperlink or frame.link
    if type(link) == "string" and link ~= "" then
        return tonumber(GetItemInfoInstant(link))
    end

    if type(frame.GetHyperlink) == "function" then
        local ok, h = pcall(frame.GetHyperlink, frame)
        if ok and type(h) == "string" and h ~= "" then
            return tonumber(GetItemInfoInstant(h))
        end
    end

    if type(frame.GetItemLocation) == "function" and _G.C_Item and type(_G.C_Item.GetItemLink) == "function" then
        local ok, loc = pcall(frame.GetItemLocation, frame)
        if ok and loc then
            local ok2, l = pcall(_G.C_Item.GetItemLink, loc)
            if ok2 and type(l) == "string" and l ~= "" then
                return tonumber(GetItemInfoInstant(l))
            end
        end
    end

    return nil
end

local function IsVaultAvailableNow()
    local C_WeeklyRewards = _G.C_WeeklyRewards
    if not C_WeeklyRewards then return true end
    if type(C_WeeklyRewards.HasAvailableRewards) ~= "function" then return true end
    local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
    if ok then return has and true or false end
    return true
end

local function ClearVaultHighlights()
    for target in pairs(VaultHighlight.active) do
        local glow = VaultHighlight.glowByTarget[target]
        if glow then
            if glow.anim then glow.anim:Stop() end
            glow:Hide()
        end
        VaultHighlight.active[target] = nil
    end
end

local function EnsureVaultHooks()
    if VaultHighlight.hooked then return end
    local frame = rawget(_G, "WeeklyRewardsFrame")
    if not frame or type(frame.HookScript) ~= "function" then
        return
    end

    VaultHighlight.hooked = true
    frame:HookScript("OnShow", function()
        -- Delay one frame so the reward buttons are populated.
        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            _G.C_Timer.After(0, function()
                -- Refresh when the window is shown.
                if MP and MP.BestInSlotNotificationHandler and MP.BestInSlotNotificationHandler.__UpdateVaultHighlights then
                    MP.BestInSlotNotificationHandler:__UpdateVaultHighlights()
                end
            end)
        end
    end)
    frame:HookScript("OnHide", function()
        ClearVaultHighlights()
    end)

    if type(frame.Update) == "function" then
        hooksecurefunc(frame, "Update", function()
            if MP and MP.BestInSlotNotificationHandler and MP.BestInSlotNotificationHandler.__UpdateVaultHighlights then
                MP.BestInSlotNotificationHandler:__UpdateVaultHighlights()
            end
        end)
    end
end

function NIH:__UpdateVaultHighlights()
    local frame = rawget(_G, "WeeklyRewardsFrame")
    if not frame or not frame.IsShown or not frame:IsShown() then
        ClearVaultHighlights()
        return
    end

    EnsureVaultHooks()

    if not IsVaultAvailableNow() then
        ClearVaultHighlights()
        return
    end

    local selected = GetSelectedBiSItemIDs()
    if type(selected) ~= "table" then
        ClearVaultHighlights()
        return
    end

    local r, g, b, a = GetAvailabilityColor()

    local newActive = {}
    local seen = {}

    local function Visit(node)
        if not node or seen[node] then return end
        seen[node] = true

        local isButton = (type(node.GetObjectType) == "function" and node:GetObjectType() == "Button")
        local hasIcon = node.Icon or node.icon or node.IconTexture
        if isButton and hasIcon then
            local itemID = GetCandidateItemID(node)
            if itemID and selected[itemID] then
                local glow = VaultHighlight.glowByTarget[node]
                if not glow then
                    glow = CreatePixelGlow(node)
                    VaultHighlight.glowByTarget[node] = glow
                end
                if glow then
                    SetGlowColor(glow, r, g, b, a)
                    glow:Show()
                    if glow.anim and not glow.anim:IsPlaying() then
                        glow.anim:Play()
                    end
                    newActive[node] = true
                end
            end
        end

        if type(node.GetChildren) == "function" then
            for child in node:GetChildren() do
                Visit(child)
            end
        end
    end

    Visit(frame)

    -- Remove glows that are no longer active.
    for target in pairs(VaultHighlight.glowByTarget) do
        if VaultHighlight.glowByTarget[target] and not newActive[target] then
            local glow = VaultHighlight.glowByTarget[target]
            if glow then
                if glow.anim then glow.anim:Stop() end
                glow:Hide()
            end
        end
    end

    VaultHighlight.active = setmetatable(newActive, { __mode = "k" })
end

local function OnChatMsgLoot(message)
    local raw = type(message) == "string" and message:match(LOOT_SELF_PATTERN)
    if not raw then return end

    local quantity = 1
    local qtyMatch = raw:match("x(%d+)%.?$")
    if not qtyMatch then
        qtyMatch = raw:match("%sx(%d+)%s*%.?$")
    end
    if qtyMatch then
        quantity = tonumber(qtyMatch) or 1
        raw = raw:gsub("%s*x%d+%.?$", "")
    end

    local itemLink = raw:match("(|c%x+|Hitem:[^|]+|h%[[^]]+%]|h|r)") or raw
    if not itemLink then return end

    local info = GetItemInfoTable(itemLink, nil)
    if info and info.link then
        ProcessLootItem(info.link, quantity, nil)
        return
    end

    GetItemInfoTable(itemLink, function(filled)
        if not filled or not filled.link then
            Logger.Error("BestInSlotNotificationHandler: Failed to resolve item info for: " .. tostring(itemLink))
            return
        end
        ProcessLootItem(filled.link, quantity, nil)
    end)
end

local function HandleEvent(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
        local msg = ...
        OnChatMsgLoot(msg)
    elseif event == "START_LOOT_ROLL" then
        local rollID = ...
        OnStartLootRoll(rollID)
    elseif event == "WEEKLY_REWARDS_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        CheckGreatVaultForBiS()
        if NIH and NIH.__UpdateVaultHighlights then
            NIH:__UpdateVaultHighlights()
        end
    end
end

function NIH:IsEnabled()
    return self.enabled
end

function NIH:Enable()
    if self.enabled then return end
    self.enabled = true

    if self.frame then
        self.frame:UnregisterAllEvents()
        self.frame:SetScript("OnEvent", nil)
        self.frame = nil
    end

    self.frame = CreateFrame("Frame", "TwichUIMythicPlusBiSNotificationListener")
    self.frame:SetScript("OnEvent", HandleEvent)
    self.frame:RegisterEvent("CHAT_MSG_LOOT")
    self.frame:RegisterEvent("START_LOOT_ROLL")
    self.frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Hook Great Vault UI when Blizzard_WeeklyRewards loads.
    if not self.__vaultHighlightListener then
        self.__vaultHighlightListener = CreateFrame("Frame")
        self.__vaultHighlightListener:RegisterEvent("ADDON_LOADED")
        self.__vaultHighlightListener:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_WeeklyRewards" then
                EnsureVaultHooks()
                if self.__UpdateVaultHighlights then
                    self:__UpdateVaultHighlights()
                end
            end
        end)
    end

    -- If it's already loaded, hook immediately.
    if rawget(_G, "WeeklyRewardsFrame") then
        EnsureVaultHooks()
    end

    -- reset per-session availability caches
    self.__rollNotified = {}
    self.__vaultNotified = {}

    if MP.BestInSlotNotificationFrame and MP.BestInSlotNotificationFrame.Initialize then
        MP.BestInSlotNotificationFrame:Initialize()
    end

    Logger.Debug("BestInSlot notifications enabled")
end

function NIH:Disable()
    if not self.enabled then return end
    self.enabled = false

    if self.frame then
        self.frame:UnregisterAllEvents()
        self.frame:SetScript("OnEvent", nil)
        self.frame = nil
    end

    if self.__vaultHighlightListener then
        self.__vaultHighlightListener:UnregisterAllEvents()
        self.__vaultHighlightListener:SetScript("OnEvent", nil)
        self.__vaultHighlightListener = nil
    end
    ClearVaultHighlights()

    Logger.Debug("BestInSlot notifications disabled")
end

function NIH:Initialize()
    if self.initialized then return end
    self.initialized = true

    local enabled = CM:GetProfileSettingSafe(KEY_PREFIX .. "enabled", true)
    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

--- Developer/testing helper: simulate looting an item.
--- @param item string|number itemID or itemLink
--- @param quantity number|nil
--- @param overrideILvl number|nil
function NIH:TestSimulateLoot(item, quantity, overrideILvl)
    quantity = tonumber(quantity) or 1
    if quantity < 1 then quantity = 1 end

    local normalized = item
    if type(item) == "string" then
        local trimmed = item:match("^%s*(.-)%s*$")
        local asNumber = tonumber(trimmed)
        if asNumber then
            normalized = asNumber
        else
            normalized = trimmed
        end
    end

    local function Fire(link)
        if not link then
            Logger.Error("BestInSlotNotificationHandler:TestSimulateLoot failed to resolve item: " .. tostring(item))
            return
        end
        ProcessLootItem(link, quantity, overrideILvl)
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)

    if info and info.link then
        Fire(info.link)
    end
end

--- Developer/testing helper: force-show a notification (bypasses BiS selection / owned upgrade logic).
--- @param item string|number itemID or itemLink
--- @param kind "NEW"|"UPGRADE"|"FOUND"|string|nil
--- @param receivedILvl number|nil
--- @param previousILvl number|nil
--- @param quantity number|nil
function NIH:TestForceNotification(item, kind, receivedILvl, previousILvl, quantity)
    quantity = tonumber(quantity) or 1
    if quantity < 1 then quantity = 1 end

    local normalized = item
    if type(item) == "string" then
        local trimmed = item:match("^%s*(.-)%s*$")
        local asNumber = tonumber(trimmed)
        if asNumber then
            normalized = asNumber
        else
            normalized = trimmed
        end
    end

    local function Fire(link)
        if not link then
            Logger.Error("BestInSlotNotificationHandler:TestForceNotification failed to resolve item: " .. tostring(item))
            return
        end

        PlayNotificationSound("notificationSound", "TwichUI Green Dude Gets Loot")
        ShowAndLog(kind or "FOUND", link, tonumber(receivedILvl) or nil, tonumber(previousILvl) or nil, quantity)
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)

    if info and info.link then
        Fire(info.link)
    end
end

--- Developer/testing helper: simulate a START_LOOT_ROLL event for an item.
--- This uses the same internal path as the real event handler, including GetLootRollItemLink/GetLootRollItemInfo.
--- @param item string|number itemID or itemLink
--- @param quantity number|nil
--- @param ensureSelected boolean|nil Temporarily add the item to the BiS selection list for the test.
--- @param ensureEnabled boolean|nil Temporarily enable the Roll availability setting for the test.
function NIH:TestSimulateAvailabilityRoll(item, quantity, ensureSelected, ensureEnabled)
    quantity = tonumber(quantity) or 1
    if quantity < 1 then quantity = 1 end

    if ensureSelected == nil then ensureSelected = true end
    if ensureEnabled == nil then ensureEnabled = true end

    local normalized = item
    if type(item) == "string" then
        local trimmed = item:match("^%s*(.-)%s*$")
        local asNumber = tonumber(trimmed)
        if asNumber then
            normalized = asNumber
        else
            normalized = trimmed
        end
    end

    local function Fire(link)
        if not link then
            Logger.Error("BestInSlotNotificationHandler:TestSimulateAvailabilityRoll failed to resolve item: " ..
                tostring(item))
            return
        end

        local function DoSim()
            self.__rollNotified = self.__rollNotified or {}
            self.__testRollCounter = (tonumber(self.__testRollCounter) or 90000) + 1
            local rollID = self.__testRollCounter
            self.__rollNotified[rollID] = nil

            local oldLinkFn = GetLootRollItemLink
            local oldInfoFn = GetLootRollItemInfo

            GetLootRollItemLink = function(id)
                if tonumber(id) == tonumber(rollID) then
                    return link
                end
                if type(oldLinkFn) == "function" then
                    return oldLinkFn(id)
                end
                return nil
            end

            GetLootRollItemInfo = function(id)
                if tonumber(id) == tonumber(rollID) then
                    -- texture, name, count, ...; only count is used by our handler.
                    return nil, nil, quantity
                end
                if type(oldInfoFn) == "function" then
                    return oldInfoFn(id)
                end
                return nil
            end

            local ok, err = pcall(function()
                OnStartLootRoll(rollID)
            end)

            GetLootRollItemLink = oldLinkFn
            GetLootRollItemInfo = oldInfoFn

            if not ok then
                Logger.Error("TestSimulateAvailabilityRoll error: " .. tostring(err))
            end
        end

        local function Run()
            if ensureSelected then
                WithTemporaryBiSSelection(link, DoSim)
            else
                DoSim()
            end
        end

        if ensureEnabled then
            WithTemporaryProfileSetting(KEY_PREFIX .. "availabilityRollEnabled", true, Run)
        else
            Run()
        end
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)
    if info and info.link then
        Fire(info.link)
    end
end

--- Developer/testing helper: simulate Great Vault availability containing a BiS item.
--- This uses the same internal scanning path as the real WEEKLY_REWARDS_UPDATE handler.
--- @param item string|number itemID or itemLink
--- @param ensureSelected boolean|nil Temporarily add the item to the BiS selection list for the test.
--- @param ensureEnabled boolean|nil Temporarily enable the Vault availability setting for the test.
function NIH:TestSimulateAvailabilityVault(item, ensureSelected, ensureEnabled)
    if ensureSelected == nil then ensureSelected = true end
    if ensureEnabled == nil then ensureEnabled = true end

    local normalized = item
    if type(item) == "string" then
        local trimmed = item:match("^%s*(.-)%s*$")
        local asNumber = tonumber(trimmed)
        if asNumber then
            normalized = asNumber
        else
            normalized = trimmed
        end
    end

    local function Fire(link)
        if not link then
            Logger.Error("BestInSlotNotificationHandler:TestSimulateAvailabilityVault failed to resolve item: " ..
                tostring(item))
            return
        end

        local function DoSim()
            self.__vaultNotified = self.__vaultNotified or {}
            local itemID = GetItemInfoInstant(link)
            if itemID then
                self.__vaultNotified[tonumber(itemID)] = nil
            end
            __lastVaultCheckAt = 0

            local oldWeekly = C_WeeklyRewards
            C_WeeklyRewards = {
                HasAvailableRewards = function() return true end,
                RequestRewards = function() end,
                RequestActivities = function() end,
                GetActivities = function()
                    return { { id = 424242 } }
                end,
                GetActivityItemRewards = function(_, _)
                    return { link }
                end,
            }

            local ok, err = pcall(function()
                CheckGreatVaultForBiS()
            end)

            C_WeeklyRewards = oldWeekly

            if not ok then
                Logger.Error("TestSimulateAvailabilityVault error: " .. tostring(err))
            end
        end

        local function Run()
            if ensureSelected then
                WithTemporaryBiSSelection(link, DoSim)
            else
                DoSim()
            end
        end

        if ensureEnabled then
            WithTemporaryProfileSetting(KEY_PREFIX .. "availabilityVaultEnabled", true, Run)
        else
            Run()
        end
    end

    local info = GetItemInfoTable(normalized, function(filled)
        Fire(filled and filled.link)
    end)
    if info and info.link then
        Fire(info.link)
    end
end
