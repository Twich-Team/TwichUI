-- TwichUI settings: hazard alerts (hazard/). Two pages: General (the switch, the three alert categories with their
-- sounds and test buttons, the volume channel, the built-in rules, Reset) and Rules (the auras you listed;
-- Hazard.lua's sibling HazardRules.lua draws that list and its editor). What is registered, and every value saved, is
-- the core addon's hazard/ files; this file only describes rows that call their Get/Set.
-- Nothing here is needed for the alerts to work. The sounds are played by the game; the test buttons play one sound
-- once and register nothing.

local R = TwichUI
local K = R.SettingsKit

local function HZ() return R.Hazard end
local function On() return R:Enabled("hazardAlerts") end

local TEST_WORDS = {
    none = "That category's sound is set to None, so there is nothing to play.",
    missing = "That sound is not available (its addon may be turned off), so nothing played.",
    unavailable = "The game offers no way to play it right now.",
    refused = "The game refused to play that sound.",
}

K.Page({
    key = "hazard", icon = "hazardAlerts", name = "Hazard alerts", nav = "Hazard alerts", order = 42, group = "everyday",
    description = "A sound when an aura you listed lands on you, grows or fades. Off until you turn it on.",
    keywords = "gtfo hazard alert alerts sound audio warning danger avoidable fire void ground aura debuff fail failed mechanic friendly fire high low damage move out",
    overview = {
        label = "Hazard alerts", tip = "The game plays a sound when an aura you listed lands on you, grows or fades.",
        when = function() return R.Hazard ~= nil end,
        status = function() return K.OnOff(R:Enabled("hazardAlerts")) end,
    },
    when = function() return R.Hazard ~= nil end,
    build = function()
        local Header, Toggle, Button, Under = K.Header, K.Toggle, K.Button, K.Under
        local BOOL, STRING = K.BOOL, K.STRING
        local hz = HZ()
        local A = R.HazardAlerts

        Header("Hazard alerts", "Plays a sound of your choosing when an aura you listed is put on you, grows or fades. The game itself plays it: this client gives addons no combat log, so TwichUI cannot see damage, who caused it or where you stand, and cannot tell which hits were avoidable. It only knows that a listed aura happened to you. It says nothing in chat, shows nothing on screen and does nothing until you turn it on.")
        local main = Toggle("hazardAlerts", "Play sounds for the auras I list",
            "While on, every enabled rule (yours on the Rules tab, and any built-in ones) is registered with the game as a sound for you, and only you: not your pets, group or other players. Turn it off to remove them all; nothing then listens or runs.\n\nOff is the default, and importing someone's configuration never plays anything by itself: a rule only names an aura, and you decide whether the alerts are on.")
        K.Note(main, function()
            if A.GtfoActive() then
                return "GTFO is also loaded. Both can play a sound for the same hazard, so you may hear two. Choose one to keep on; TwichUI does not change GTFO.", "warn"
            end
        end)
        Under(K.Status("State",
            function()
                if not On() then return "Off" end
                local s = A.Snapshot()
                if not s.available then return "Not offered by this client" end
                if s.pending then return "Waiting for the game's restrictions to lift" end
                return ("%d registered"):format(s.registered)
            end,
            function()
                local s = A.Snapshot()
                if not On() then return "Nothing is registered or listened for." end
                if not s.available then return "This client does not have the aura sound registration these alerts use, so nothing can play." end
                if s.pending then return "The game refuses new registrations in combat, encounters and some maps. A change made then is applied when that ends." end
                if s.wanted == 0 then return "No rule is on yet. Add one on the Rules tab." end
                if s.refused > 0 then return ("The game refused %d registration(s); a spell ID it does not accept is the usual reason."):format(s.refused) end
                return "Read when this page is drawn; it is not polled."
            end,
            "How many of your rules the game has accepted right now. The game plays the sounds; nothing here can tell whether one has played.",
            function()
                if not On() then return "quiet" end
                local s = A.Snapshot()
                if not s.available or s.refused > 0 then return "warn" end
                return "ok"
            end), main, On)

        local resettable = {}
        local function Shared(variable, key, varType, label, set)
            local setting = K.Proxy("hazard" .. variable, varType, label, hz.DEFAULTS[key],
                function() return hz.Get(key) end, set or function(value) hz.Set(key, value) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = hz.DEFAULTS[key] } end
            return setting
        end

        Header("Alert categories", "A category is how urgent a rule is, and it picks the sound. It is not a measure of damage. Friendly fire is not offered: telling it apart needs the source of a hit, which this client does not give addons.")
        for _, c in ipairs(hz.CATEGORIES) do
            local category, label, meaning = c[1], c[2], c[3]
            local cap = category:sub(1, 1):upper() .. category:sub(2)
            local box = Under(K.Checkbox(Shared(cap .. "On", category .. "On", BOOL, label .. " alerts", function(v) hz.Set(category .. "On", v and true or false) end),
                meaning .. "\n\nOff, the rules in this category are not registered at all."), main, On)
            local function CategoryOn() return On() and hz.Get(category .. "On") end
            local why = "Greyed out: turn this category on first."
            local pick = Under(K.Dropdown(Shared(cap .. "Sound", category .. "Sound", STRING, label .. " sound"),
                function()
                    local list = { { hz.NONE, "None (silent)" } }
                    for _, choice in ipairs(R:SoundChoices(hz.Get(category .. "Sound") ~= hz.NONE and hz.Get(category .. "Sound") or nil)) do list[#list + 1] = choice end
                    return list
                end,
                "TwichUI's own sounds, then every sound LibSharedMedia lists. None registers nothing for this category. A sound that has gone stays chosen and plays nothing until it is back."), box, CategoryOn, why)
            K.Note(pick, function()
                if On() and hz.Get(category .. "On") and A.MissingSound(category) then
                    return "This sound is not available right now, so this category plays nothing.", "warn"
                end
            end)
            Under(Button(label .. " test", "Play", function()
                local ok, why2 = A.TestSound(category)
                if not ok then R.Print(TEST_WORDS[why2] or "nothing played.") end
            end, "Plays this category's sound once, on the chosen volume channel. It registers nothing, uses no rule and changes no cooldown, so it works anywhere, on any class, and cannot affect the next real alert."), box, CategoryOn, why)
        end

        Header("Volume", "The game has no volume for a single sound and this registration has no volume at all, so there is no per-category volume. TwichUI never changes your game volume settings.")
        Under(K.Dropdown(Shared("Channel", "channel", STRING, "Volume channel"), function() return hz.CHOICES.channel end,
            "Which of the game's volume sliders the alerts follow. If that channel is muted or turned to zero in the game's sound settings, the alerts are silent too. Master is heard even with sound effects turned down."), main, On)

        Header("Built-in rules", "Rules that ship with TwichUI. A rule is only shipped once its spell ID has been checked on this client, so the list is short and starts empty. Turning one off here is remembered by its stable name and survives updates.")
        local builtin = R.HazardRules.Builtin()
        if #builtin == 0 then
            Under(K.Status("Shipped rules", function() return "None yet" end,
                function() return "Add the auras you care about on the Rules tab. Nothing is guessed on your behalf." end,
                "No built-in rule has been confirmed on this client yet, so none is shipped. The structure for them exists (docs/hazard-alerts.md)."), main, On)
        else
            for _, def in ipairs(builtin) do
                local id = def.id
                local setting = K.Proxy("hazardBuiltin" .. id, BOOL, def.name, true,
                    function() return not hz.IsBuiltinOff(id) end,
                    function(v) hz.SetBuiltinEnabled(id, v and true or false) end)
                if setting then
                    local cat = hz.CATEGORY[def.category]
                    Under(K.Checkbox(setting, ("%s\n\nSpell ID %d · %s · %s\nWhy: %s\nChecked: %s"):format(def.name, def.spell, cat[2],
                        hz.TRIGGER[def.trigger][2]:lower(), def.why, def.source)), main, On)
                end
            end
            Under(Button("Built-in rules", "Turn all on", function() hz.ResetBuiltin() end,
                "Turns every built-in rule you switched off back on. Your own rules are not touched."), main, On)
        end

        Header("Reset", "The reset says what it covers. Your rules and the built-in choices are kept; they have their own controls.")
        K.ResetButton("Hazard alert settings", resettable, function() hz.ResetSettings() end,
            "Puts the categories on or off, their sounds and the volume channel back to their defaults. The switch, your rules and the built-in rule choices are kept.")
    end,
})
