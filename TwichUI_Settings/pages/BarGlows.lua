-- TwichUI settings: Action bar glows (glows/). Cards for the feature itself, group buffs, cooldowns and supplies, which
-- bars glow and which are faded; every row calls glows/Config.lua's Get/Set. The per-spell list and the looks are the
-- "Spells and looks" tab (BarGlowsSpells.lua). Nothing here is needed for the glows to work.

local R = TwichUI
local K = R.SettingsKit

local DOT = "  \194\183  "

local function BG() return R.BarGlows end
local function On() return R:Enabled("barGlows") end

local function KindsOn()
    local C, bg = R.BarGlowCatalog, BG()
    local n = 0
    for _, kind in ipairs(C.LIST_ORDER) do if bg.TypeEnabled(kind) then n = n + 1 end end
    return n, #C.LIST_ORDER
end

-- The weapon buffs this class can keep up on a hand (and the ones added), for the hand's dropdown.
local function WeaponChoices(hand)
    local C, bg, ST = R.BarGlowCatalog, BG(), R.BarGlowState
    local _, class = UnitClass("player")
    local out = { { "auto", "Automatic", "The one you put on that hand last; else the first you have that is turned on." } }
    for _, e in ipairs(C.For("weaponBuff", class)) do
        if e.slot == "both" or e.slot == hand then
            out[#out + 1] = { e.key, (e.spell and ST.Display(e.spell)) or e.label }
        end
    end
    for _, a in ipairs(bg.Added()) do
        if a.kind == "weaponBuff" and (a.slot == "both" or a.slot == hand) then
            local label = a.spell and (ST.Display(a.spell) or ("Spell " .. a.spell)) or (ST.ItemDisplay(a.item) or ("Item " .. a.item))
            out[#out + 1] = { bg.AddedKey(a), label }
        end
    end
    local current = bg.Weapon(hand)
    local listed = false
    for _, c in ipairs(out) do if c[1] == current then listed = true end end
    if not listed then out[#out + 1] = { current, current .. " (not available)" } end
    return out
end

local function GroupFromChoices()
    local out = {}
    for n = 1, 5 do out[#out + 1] = { n, n == 1 and "1 member missing" or (n .. " members missing") } end
    return out
end

K.Page({
    key = "barGlows", icon = "barGlows", name = "Action bar glows", nav = "Bar glows", order = 63, group = "class",
    description = "Your action bar buttons glow when something wants doing: a missing buff, a weapon buff, a seal or tracking, a low reagent, a ready cooldown, a proc or an old rank.",
    keywords = "glow glows glowing bars action bar button buff missing weapon poison imbue seal tracking reagent stock cooldown ready proc overpower revenge execute riposte rank faded fade highlight reminder",
    overview = {
        label = "Action bar glows", tip = "Your action bar buttons glow when a buff is missing, a cooldown is ready, a proc can be used and more.",
        when = function() return R.BarGlows ~= nil end,
        status = function() return K.OnOff(R:Enabled("barGlows")) end,
    },
    when = function() return R.BarGlows ~= nil and R.BarGlowController ~= nil end,
    build = function()
        local bg, CT = BG(), R.BarGlowController
        local Under = K.Under
        local BOOL, NUMBER, STRING = K.BOOL, K.NUMBER, K.STRING
        local resettable = {}
        local function Keep(s, default)
            if s then resettable[#resettable + 1] = { setting = s, default = default } end
            return s
        end
        local function Name(key) return "barGlows" .. key:sub(1, 1):upper() .. key:sub(2) end
        local main
        local function Check(key, label, tip, isOn, why)
            local s = Keep(K.Proxy(Name(key), BOOL, label, bg.DEFAULTS[key], function() return bg.Get(key) end,
                function(v) bg.Set(key, v and true or false) end), bg.DEFAULTS[key])
            return Under(K.Checkbox(s, tip), main, isOn or On, why)
        end
        local function Range(key, label, tip, isOn, why)
            local lim = bg.LIMITS[key]
            local s = Keep(K.Proxy(Name(key), NUMBER, label, bg.DEFAULTS[key], function() return bg.Get(key) end,
                function(v) bg.Set(key, math.floor(v + 0.5)) end), bg.DEFAULTS[key])
            return Under(K.Slider(s, lim[1], lim[2], tip), main, isOn or On, why)
        end

        -- 1. The feature
        K.Card({
            title = "Action bar glows", icon = "barGlows",
            what = "A button on your action bars glows when it is the one to press: a buff of yours is missing, a weapon buff, seal or tracking is off, a reagent runs low, an important cooldown is back, a proc can be used, or the button holds an old rank.",
            summary = function()
                if not On() then return "Off." end
                local n, total = KindsOn()
                local parts = { ("%d of %d kinds on"):format(n, total) }
                if bg.Get("quietInTowns") then parts[#parts + 1] = "quiet in towns" end
                return table.concat(parts, DOT)
            end,
            consequence = "It only reads and draws: nothing is ever cast, used or clicked for you, and nothing is said in chat. Each kind and each spell can be turned off, and each has its own look, on the Spells and looks tab. A spell that is not on your bars has no button to glow; a message can still say it is missing.",
            details = {
                { "Which bars?", "Blizzard's action bars and stance bar, and EllesmereUI's Action Bars (they keep the same slots). Turn a bar off below to keep it quiet." },
                { "What counts as missing?", "A buff is missing when none of its names is on you: any rank, and its group version (Arcane Brilliance counts for Arcane Intellect). Where you use one of a set (an aspect, an armor, a paladin aura, a blessing on yourself, a seal, a tracking), any of them is enough, and the one you used last glows when none is up." },
                { "What can't it see?", "When the game hides auras or cooldowns (it can, in some fights), those reminders wait and nothing glows on a guess. Other players' buffs are only looked at out of combat." },
            },
        })
        main = K.Toggle("barGlows", "Make my action buttons glow",
            "On: buttons glow by the rules below and on the Spells and looks tab. Off: no glows, faded bars or messages, and nothing is listened for. Your choices are kept either way.")
        K.Status("Right now",
            function()
                if not On() then return "Off" end
                local due = CT.Due()
                local showing = 0
                for _, d in ipairs(due) do if d.showing then showing = showing + 1 end end
                if #due == 0 then return "Nothing due" end
                return ("%d due, %d glowing"):format(#due, showing)
            end,
            function()
                if not On() then return nil end
                local due = CT.Due()
                if #due == 0 then return "Read when this page is drawn." end
                local names = {}
                for i = 1, math.min(4, #due) do names[i] = due[i].text end
                return table.concat(names, "; ") .. (#due > 4 and " ..." or "")
            end,
            "What is due at the last look, and how many of those are glowing (a reminder can be due but held back by its \"when\", or waiting between repeats). Read when this page is drawn; it is not polled.",
            function() return On() and "ok" or "quiet" end)
        Check("quietInTowns", "Stay quiet in towns and inns",
            "No glows, messages or sounds while you are resting in a town or an inn, out of combat. Low reagents and low stock set to \"Alert in town\" are the exception: that is where you can buy more.")
        Under(K.Button("Spells and looks", "Open", function() R:OpenSettings("barGlowsSpells") end,
            "Every kind and every spell, each with its own on/off and look: the glow's art, color, strength, size, speed and motion; when it may show; how long it glows and how often it comes again; its message and sound."), main, On)

        -- 2. Messages
        K.Card({
            title = "Messages", icon = "notifications", switch = false,
            what = "A reminder whose message is on shows a small card under the zone arrival card's place, drawn in the same look: the spell's name, the bronze rule and a line saying what is wanted.",
            summary = function()
                local parts = { bg.Get("noticeFade") and ("fades after %d s"):format(bg.Get("noticeSeconds")) or "stays until done" }
                if bg.Get("noticeIcon") then parts[#parts + 1] = "with the spell's icon" end
                return table.concat(parts, DOT)
            end,
            consequence = "Its fonts, colors, text size, outline, accent and backdrop are the zone arrival card's, set under Notifications > Notification appearance; Reduced motion there stops its small rise. A card goes as soon as its reminder is done (you cast the buff, used the cooldown ...). At most three show at once, the newest on top. Which reminders have a message is chosen per kind or spell on the Spells and looks tab (low reagents, low stock and old ranks have one as they ship).",
        })
        Check("noticeIcon", "Show the spell's icon",
            "The spell's or item's icon beside the card's title.")
        Check("noticeFade", "Fade out after a while",
            "On: a card fades after the time below, or sooner when its reminder is done. Off: it stays until its reminder is done.")
        Range("noticeSeconds", "Fade out after (seconds)",
            "How long a card stays before it fades, counted again each time its reminder repeats.",
            function() return On() and bg.Get("noticeFade") end, "Greyed out: cards stay until their reminder is done.")
        Under(K.Button("Sample message", "Show", function() R.BarGlowNotice.Preview() end,
            "Shows a made-up message card where the cards appear, drawn with your choices, for a few seconds. Nothing is checked or remembered."), main, On)

        -- 2. Group buffs
        K.Card({
            title = "Group buffs", icon = "profilesSharing", switch = false,
            what = "Out of combat in a group, members in range who are missing one of your buffs make its button glow, with their names in its message.",
            summary = function()
                local parts = {}
                if bg.Get("partyBuffs") then parts[#parts + 1] = ("party: group version from %d"):format(bg.Get("partyGroupFrom")) end
                if bg.Get("raidBuffs") then parts[#parts + 1] = ("raid: from %d"):format(bg.Get("raidGroupFrom")) end
                return #parts > 0 and table.concat(parts, DOT) or "Only your own buffs are watched."
            end,
            consequence = "Only out of combat, only members in range of the spell. The group version (Prayer of Fortitude, Arcane Brilliance, Gift of the Wild, a Greater Blessing for one class) glows instead once enough are missing it, counting you but never you alone, and only while its reagent is in your bags. A paladin's blessings are watched by class: the one you last gave each class.",
        })
        Check("partyBuffs", "Party members missing my buffs", "In a party: members in range who lack one of your buffs make its button glow. Off: only your own buffs are watched in a party.")
        local from = bg.LIMITS.partyGroupFrom
        Under(K.Dropdown(Keep(K.Proxy("barGlowsPartyGroupFrom", NUMBER, "Party: group version from", bg.DEFAULTS.partyGroupFrom,
            function() return bg.Get("partyGroupFrom") end, function(v) bg.Set("partyGroupFrom", v) end), bg.DEFAULTS.partyGroupFrom),
            GroupFromChoices, ("How many missing a buff (you counted, never you alone) make the group version glow in a party, %d to %d."):format(from[1], from[2])),
            main, function() return On() and bg.Get("partyBuffs") end, "Greyed out: party members are not watched.")
        Check("raidBuffs", "Raid members missing my buffs", "In a raid: members in range who lack one of your buffs make its button glow. Off: only your own buffs are watched in a raid.")
        Under(K.Dropdown(Keep(K.Proxy("barGlowsRaidGroupFrom", NUMBER, "Raid: group version from", bg.DEFAULTS.raidGroupFrom,
            function() return bg.Get("raidGroupFrom") end, function(v) bg.Set("raidGroupFrom", v) end), bg.DEFAULTS.raidGroupFrom),
            GroupFromChoices, "How many missing a buff make the group version glow in a raid."),
            main, function() return On() and bg.Get("raidBuffs") end, "Greyed out: raid members are not watched.")

        -- 3. Cooldowns and supplies
        K.Card({
            title = "Cooldowns, weapons and supplies", icon = "vendorRestocking", switch = false,
            what = "When a ready cooldown glows, which weapon buff you keep up on each hand, and how few is low.",
            summary = function()
                local parts = { ("reagents below %d"):format(bg.Get("reagentBelow")), ("items below %d"):format(bg.Get("stockBelow")) }
                if bg.Get("cooldownsAtFightStart") then parts[#parts + 1] = "cooldowns at fight start" end
                return table.concat(parts, DOT)
            end,
            consequence = "A reagent or item can have its own limit on the Spells and looks tab; a few reagents ship with their own (Soul Shards 3, Symbols of Kings 20 ...).",
        })
        Check("cooldownsAtFightStart", "Ready cooldowns also glow as a fight starts",
            "Off: a ready cooldown glows when it comes back. On: as a fight starts, every ready cooldown glows too, as a reminder to use it.")
        for _, hand in ipairs(bg.HANDS) do
            local label = hand == "mainHand" and "Main-hand weapon buff" or "Off-hand weapon buff"
            Under(K.Dropdown(Keep(K.Proxy(hand == "mainHand" and "barGlowsWeaponMain" or "barGlowsWeaponOff", STRING, label, "auto",
                function() return bg.Weapon(hand) end, function(v) bg.SetWeapon(hand, v) end), "auto"),
                function() return WeaponChoices(hand) end,
                "Which weapon buff glows when that hand has none. Automatic: the one you put on that hand last, else the first you have. Only what your class can use is listed, with what you added."), main, On)
        end
        Range("reagentBelow", "Reagents are low below", "A spell's reagent counts as low when you carry fewer than this (unless the reagent has a limit of its own).")
        Range("stockBelow", "Items are low below", "An item you added under Low stock counts as low below this (unless it has a limit of its own).")

        -- 4. Bars
        K.Card({
            title = "Bars that glow", icon = "reminderPlacement", switch = false,
            what = "Which bars' buttons may glow. Turn one off to keep it quiet, for example a bar that repeats spells shown elsewhere.",
            summary = function()
                local off = {}
                for _, bar in ipairs(bg.BARS) do if not bg.BarOn(bar) then off[#off + 1] = bg.BarLabel(bar) end end
                return #off == 0 and "Every bar." or ("Quiet: " .. table.concat(off, ", "))
            end,
            consequence = "Bars 9 and 10 exist only with EllesmereUI's Action Bars. The stance bar holds paladin auras, stealth and forms.",
        })
        for _, bar in ipairs(bg.BARS) do
            local id = bar:sub(1, 1):upper() .. bar:sub(2)
            Under(K.Checkbox(Keep(K.Proxy("barGlows" .. id .. "On", BOOL, bg.BarLabel(bar), true,
                function() return bg.BarOn(bar) end, function(v) bg.SetBar(bar, v and true or false) end), true),
                "Buttons on this bar may glow."), main, On)
        end

        -- 5. Faded bars
        K.Card({
            title = "Faded until they glow", icon = "appearance", switch = false,
            what = "A bar whose buttons are faded while they don't glow; a glowing one shows in full, so what wants doing stands out.",
            summary = function()
                local on = {}
                for _, bar in ipairs(bg.BARS) do if bg.BarFaded(bar) then on[#on + 1] = bg.BarLabel(bar) end end
                return #on == 0 and "No bar is faded." or (table.concat(on, ", ") .. DOT .. bg.Get("fadedOpacity") .. "%")
            end,
            consequence = "It sets the buttons' own opacity and puts it back when you turn it off. A bar addon that fades bars itself (EllesmereUI's mouseover fading) still does so on top.",
        })
        for _, bar in ipairs(bg.BARS) do
            local id = bar:sub(1, 1):upper() .. bar:sub(2)
            Under(K.Checkbox(Keep(K.Proxy("barGlows" .. id .. "Faded", BOOL, "Fade " .. bg.BarLabel(bar), false,
                function() return bg.BarFaded(bar) end, function(v) bg.SetFaded(bar, v and true or false) end), false),
                "This bar's buttons are faded while they don't glow."), main, On)
        end
        Range("fadedOpacity", "Faded opacity (%)", "How visible a faded bar's buttons are while they don't glow.",
            function() return On() and bg.AnyFaded() end, "Greyed out: no bar is faded.")

        K.ResetButton("Reset action bar glows", resettable, function() bg.ResetAll() end,
            "Puts every setting on this page and every look and on/off on the Spells and looks tab back as they ship. The spells and items you added are kept (remove them on their rows), and so is what each character used last.")
    end,
})
