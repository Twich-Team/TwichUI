local T = unpack(Twich)
local MythicPlusModule = T:GetModule("MythicPlus")

--- @class MythicPlusSummarySubmodule
local Summary = MythicPlusModule.Summary or {}
MythicPlusModule.Summary = Summary

local function CreateSummaryPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:Hide()

    -- Blank panel for now

    return panel
end

function Summary:Initialize()
    if self.initialized then return end
    self.initialized = true

    if MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.RegisterPanel then
        MythicPlusModule.MainWindow:RegisterPanel("summary", function(parent, window)
            return CreateSummaryPanel(parent)
        end, nil, nil, { label = "Summary", order = 10 })
    end
end
