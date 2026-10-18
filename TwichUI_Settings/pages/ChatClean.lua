-- TwichUI settings: Chat cleaning (modules/ChatClean.lua): whether it is on, what it cleans and what each built-in
-- filter does. Choosing channels and filters, custom rules, and the live view with the sample tester are its tabs
-- (pages/ChatCleanChannels.lua, ChatCleanRules.lua, ChatCleanLive.lua).

local R = TwichUI
local K = R.SettingsKit

local function CC() return R.ChatClean end

-- "General, Trade" for the channels being cleaned (with something to check), or nil.
local function CleanedNames()
    local names = {}
    for _, ch in ipairs(CC().KnownChannels()) do
        local e = ch.choice
        if e and e.on then names[#names + 1] = ch.label end
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

-- The channels a built-in filter is on in, as names.
local function CategoryNames(key)
    local names = {}
    for _, ch in ipairs(CC().KnownChannels()) do
        local e = ch.choice
        if e and e.on and e[key] then names[#names + 1] = ch.label end
    end
    return names
end

-- What turning it on will do, named before it is done.
local function EnableText()
    local lines = {}
    for _, ch in ipairs(CC().KnownChannels()) do
        local e = ch.choice
        if e and e.on then
            local what = {}
            for _, c in ipairs(CC().CATEGORIES) do if e[c.key] then what[#what + 1] = c.label:lower() end end
            lines[#lines + 1] = ("  %s: %s"):format(ch.label, #what > 0 and table.concat(what, ", ") or "custom rules only")
        end
    end
    local rules = 0
    for _, rule in ipairs(CC().Rules()) do if rule.enabled then rules = rules + 1 end end
    local body = #lines > 0 and table.concat(lines, "\n") or "  No channel is chosen yet, so nothing is hidden until you choose one on the Channels tab."
    return ("Turn on chat cleaning?\n\nTwichUI will hide matching messages in:\n%s%s\n\nWhispers, party, raid, guild, officer, say and yell, system messages, combat text and channels you didn't choose are never looked at. Messages from you, your friends, your guild and your group are never hidden. Nothing is reported, ignored or sent. Live view shows what is hidden while it is open."):format(
        body, rules > 0 and ("\n  and %d custom %s on"):format(rules, rules == 1 and "rule" or "rules") or "")
end

-- A change made anywhere (a tab, a profile change, an import) shows on the open page.
if R.ChatClean then R.ChatClean.OnChange(function() K.RefreshOverview() end) end

K.Page({
    key = "chatClean", name = "Chat cleaning", order = 35, group = "everyday",
    description = "Hide unwanted messages, such as gold-selling spam, in the public channels you choose.",
    keywords = "chat spam filter clean cleaning hide block trade general channel gold seller advert advertisement recruitment repeat repeated keyword word badboy",
    when = function() return R.ChatClean ~= nil end,
    overview = {
        label = "Chat cleaning", tip = "Hide unwanted messages, such as gold-selling spam, in the public channels you choose.",
        status = function()
            if not CC().Enabled() then return K.OnOff(false) end
            local names = CleanedNames()
            return K.OnOff(CC().Active(), names or "On", "Nothing chosen")
        end,
    },
    build = function()
        local Header, Button, Status = K.Header, K.Button, K.Status
        local toggleRow
        Header("Chat cleaning", "Hides unwanted messages in the public channels you choose, such as General and Trade, before they reach your chat (EllesmereUI's chat included). Whispers, party, raid, guild, officer, say and yell, system messages and combat text are never looked at. Nothing is reported, ignored or blocked, and nothing is sent.")
        toggleRow = K.ProxyToggle("chatClean", "Clean public channels",
            "Hides messages that match your chosen filters and rules, only in the channels you chose. Messages from you, your friends (Battle.net friends too), your guild and your group are never hidden.\n\nOff by default. Turning it on shows what it will hide first. General and Trade with the spam and repeat filters are chosen for you to review on the Channels tab.",
            false, function() return CC().Enabled() end,
            function(value)
                if value and not CC().Enabled() then
                    R.Interact.Confirm("TWICHUI_CHATCLEAN_ON", EnableText(), function()
                        R:SetEnabled("chatClean", true)
                        if toggleRow then toggleRow:GetSetting():NotifyUpdate() end
                        K.RefreshOverview()
                    end, { accept = "Turn on" })
                    return
                end
                R:SetEnabled("chatClean", value and true or false)
                K.RefreshOverview()
            end)
        K.Note(toggleRow, function()
            if CC().Enabled() and not CC().Active() then
                return "On, but no channel has a filter or rule chosen, so nothing is hidden. Choose on the Channels tab.", "warn"
            end
        end)
        Status("Channels cleaned", function() return CleanedNames() or "None chosen" end, function()
            if not CC().Customized() then return "The recommended choice, ready for you to review. Nothing is hidden until chat cleaning is on." end
            return "Channels are recognised by the game's own channel ID, so they keep their settings when your channel numbers change, in other zones and in any language. Custom channels are recognised by name."
        end, "The channels TwichUI looks at. Everything else in your chat is left alone.")
        Button("Channels and filters", "Choose", function() R:OpenSettings("chatCleanChannels") end,
            "Choose which channels are cleaned and which built-in filters each one uses.")

        Header("Built-in filters", "Chosen per channel on the Channels tab. Each looks for several signs together, so ordinary trade messages, links, other languages and capital letters are not hidden for that alone. None of them is perfect.")
        for _, c in ipairs(CC().CATEGORIES) do
            Status(c.label, function()
                local names = CategoryNames(c.key)
                if #names == 0 then return "Not used" end
                return "On in " .. table.concat(names, ", ")
            end, function() return c.text end, c.text)
        end

        Header("Custom rules", "Your own words or patterns to hide, each with the channels it applies to.")
        Status("Your rules", function()
            local all, on = 0, 0
            for _, rule in ipairs(CC().Rules()) do
                all = all + 1
                if rule.enabled then on = on + 1 end
            end
            if all == 0 then return "None yet" end
            return ("%d %s, %d on"):format(all, all == 1 and "rule" or "rules", on)
        end, nil, "How many custom rules you have, and how many of them are on.")
        Button("Custom rules", "Edit", function() R:OpenSettings("chatCleanRules") end,
            "Add, edit, turn on or off and remove rules: text to find (punctuation is literal), wildcards, or Lua patterns for experts.")

        Header("Live view and test", "See what TwichUI hides while you watch, and try a sample message against your rules without sending anything.")
        Button("Live view", "Open", function() R:OpenSettings("chatCleanLive") end,
            "Messages hidden while the live view is open, with the channel, sender and the filter or rule that hid them. Nothing is kept once it closes.")
    end,
})
