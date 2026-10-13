-- TwichUI settings: Gear comparison (upgrade hints, bag marks), and Stat weights under it (gear/Window.lua's
-- own frame, shown as a page).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "gear", name = "Gear comparison", order = 10, group = "class",
    description = "Quiet upgrade hints in item tooltips and bags. A rough guide from item stats, not a simulation.",
    keywords = "upgrade item level ilvl compare tooltip bags",
    overview = {
        label = "Gear comparison", tip = "Quiet upgrade hints in item tooltips and bags, and the stat weights behind them.",
        when = function() return R.GearPrefs ~= nil end,
        status = function() return K.OnOff(R:Enabled("gearHints") or R:Enabled("gearBagIcons")) end,
    },
    build = function()
        local Header, Toggle, Button, Choice, ProxyToggle, Advanced, Under = K.Header, K.Toggle, K.Button, K.Choice, K.ProxyToggle, K.Advanced, K.Under
        local STRING, NUMBER = K.STRING, K.NUMBER

        Header("Upgrade hints", "Quiet upgrade hints for your class and main talent tree. A rough estimate from item stats, not a simulation. Nothing to set up first: TwichUI starts from its own rough stat weights for each class and tree, which you can change under Stat weights if you follow a guide.")
        Toggle("gearHints", "Upgrade hints in item tooltips",
            "Adds a short line to an item's tooltip when it looks like an upgrade for your class and main talent tree, such as \"Likely upgrade for Fury\". Hold Shift (your compare-items key) to see why.\n\nWorks as soon as it is on, using TwichUI's built-in rough stat weights for your class and tree; you don't have to enter anything. No hint is shown for a class TwichUI has no weights for.\n\n\"Use:\" and \"Chance on hit:\" effects aren't weighed.")
        local bags = Toggle("gearBagIcons", "Mark upgrades in my bags",
            "A small mark in the corner of bag slots holding gear the tooltip would call an upgrade, fainter for possible upgrades. Works with Blizzard's bags and EllesmereUI Bags.")

        local P, D, B = R.GearPrefs, R.GearData, R.GearBags
        if P and D then
            Choice("gearTree", "Weigh gear for",
                "The talent tree this character's gear is weighed for. Automatic uses the tree with the most talent points when one clearly leads. Until you have spent points, while two trees are tied, or if your talents can't be read, it uses your class's usual levelling tree, and the reasoning (hold Shift over an item) says so. Choose a tree here to override it; the choice is kept for this character only.",
                NUMBER, 0,
                function() return P.TreeChoice() or 0 end,
                function(value) P.SetTreeChoice(value ~= 0 and value or nil) end,
                function()
                    local trees, _, auto = D.Trees()
                    local list = { { 0, auto and ("Automatic (" .. auto.name .. ")") or "Automatic" } }
                    for _, tree in ipairs(trees or {}) do list[#list + 1] = { tree.skillLine, tree.name } end
                    return list
                end)
        end
        if R.GearWindow then
            Button("Stat weights", "Edit", function() R:OpenSettings("statWeights") end,
                "Optional. How each of your talent trees values stats. Each starts from TwichUI's rough weights; change them only if you want hints to follow a guide: rank the stats it lists (a stat priority), or edit the numbers (stat weights). A priority with nothing ranked yet falls back to the tree's weights.")
        end
        if P then
            Advanced(Header("Advanced"))
            Advanced(ProxyToggle("gearPossible", "Show possible upgrades too",
                "Also mark gear that looks a little better, or better apart from effects the estimate can't weigh. Off: only likely upgrades and empty slots.",
                true, function() return P.Get("glancePossible") and true or false end, function(value) P.Set("glancePossible", value) end))
            Advanced(ProxyToggle("gearFuture", "Hint at gear for higher levels",
                "Gear you can't wear yet only because of its level gets a hint with that level, such as \"Likely upgrade at level 32\". Handy at the auction house.",
                true, function() return P.Get("futureLevels") and true or false end, function(value) P.Set("futureLevels", value) end))

            local function Gain(key)
                local numbers = P.STRICTNESS[key]
                return ("Likely from %d%% better than what you wear, possible from %d%%."):format(
                    math.floor(numbers.likely * 100 + 0.5), math.floor(numbers.possible * 100 + 0.5))
            end
            Advanced(Choice("gearStrictness", "How big a gain counts",
                "How much better than what you wear an item must look before it gets a hint.",
                STRING, "balanced",
                function() return P.Get("strictness") end, function(value) P.Set("strictness", value) end,
                {
                    { "cautious", "Cautious", Gain("cautious") },
                    { "balanced", "Balanced", Gain("balanced") },
                    { "eager", "Eager", Gain("eager") },
                }))
            Advanced(Choice("gearReveal", "Show the reasoning",
                "What to hold over an item to see why it got its hint: what it's compared with, the stat changes that mattered most and the weights used.",
                STRING, "compare",
                function() return P.Get("reveal") end, function(value) P.Set("reveal", value) end,
                {
                    { "compare", "Hold Shift", "Your compare-items key." },
                    { "alt", "Hold Alt" },
                    { "ctrl", "Hold Ctrl" },
                    { "always", "Always", "The reasoning shows under every item you could wear." },
                }))
            if B then
                local styles = {}
                for i, style in ipairs(B.STYLES) do styles[i] = { style.key, style.label } end
                local styleRow = Choice("gearBagStyle", "Bag mark style",
                    "The mark on upgrades in your bags. All use the game's own art. The square beside the list shows how it looks on a bag slot.",
                    STRING, "gilded",
                    function() return P.Get("bagStyle") end,
                    function(value) P.Set("bagStyle", value) end,
                    styles)
                -- A preview slot beside the dropdown, made with the row and drawn again whenever it is.
                if styleRow then
                    styleRow.extra = function(holder, control)
                        local slot = CreateFrame("Frame", nil, holder)
                        slot:SetSize(24, 24)
                        slot:SetPoint("RIGHT", control, "LEFT", -10, 0)
                        slot.back = slot:CreateTexture(nil, "BACKGROUND")
                        slot.back:SetAllPoints()
                        slot.back:SetColorTexture(0.05, 0.05, 0.05, 0.9)
                        slot.mark = slot:CreateTexture(nil, "OVERLAY")
                        slot.mark:SetPoint("TOPLEFT", 1, -1)
                        return slot
                    end
                    styleRow.refreshExtra = function(slot) B.ApplyStyle(slot.mark, P.Get("bagStyle")) end
                end
                Under(Advanced(styleRow), bags, function() return R:Enabled("gearBagIcons") end)
            end
        end
    end,
})

-- Stat weights: how each talent tree values stats (gear/Window.lua). A ranked list and a table of numbers, so
-- the feature draws it itself; the window shows it as a page.
K.Page({
    key = "statWeights", name = "Stat weights", parent = "gear", order = 11,
    description = "How each of your talent trees values stats. Optional: change them only to follow a guide.",
    keywords = "stat priority weights guide simulator rank hit crit",
    when = function() return R.GearWindow ~= nil and R.GearWindow.Frame ~= nil end,
    host = function() return R.GearWindow.Frame() end,
})
