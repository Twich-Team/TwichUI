-- TwichUI settings: Return the Favor (buffback/). Four cards (Who buffed you, Where it pauses, Thanking them,
-- Appearance) whose rows call buffback/Config.lua's Get/Set, the rows' MenuStyle look and the list's own functions
-- (the sample, Reset position). Nothing here is needed for Return the Favor to work, and nothing here casts,
-- targets or says anything.

local R = TwichUI
local K = R.SettingsKit

local DOT = "  \194\183  "

local UNLOCK_STATUS = {
    off = { "Off" },
    ["no-eui"] = { "EllesmereUI isn't installed or turned on", "Move the list by dragging its sample until it is." },
    ["no-api"] = { "This EllesmereUI has no Unlock Mode", "Move the list by dragging its sample." },
    waiting = { "Waiting for EllesmereUI", "It hasn't finished loading yet." },
    ["register-failed"] = { "EllesmereUI didn't take the mover", "Move the list by dragging its sample. /tui diagnostics has the details." },
    ["module-off"] = { "Ready", "The mover appears in Unlock Mode while Return the Favor is on." },
    active = { "In EllesmereUI's Unlock Mode", "Type /unlock and look for \"TwichUI Return the Favor\"." },
}

local PAUSED = { dungeon = "paused in this dungeon", raid = "paused in this raid", pvp = "paused in this battleground", resting = "paused while resting" }

local function BB() return R.BuffBack end
local function On() return R:Enabled("buffBack") end

K.Page({
    key = "buffBack", icon = "resurrection", name = "Return the Favor", order = 25, group = "everyday",
    description = "A short list of the players who just buffed you. Click a name to buff them back. Off until you turn it on.",
    keywords = "buff buffed rebuff return favor favour thank thanks emote manners kindness fortitude intellect mark wild blessing kings wisdom might list unlock mover",
    overview = {
        label = "Return the Favor", tip = "Who just buffed you, in a short list; click a name to buff them back.",
        when = function() return R.BuffBack ~= nil end,
        status = function() return K.OnOff(R:Enabled("buffBack")) end,
    },
    when = function() return R.BuffBack ~= nil and R.BuffBackWatch ~= nil and R.BuffBackList ~= nil end,
    build = function()
        local MS = R.MenuStyle
        local bb, Wt, L, U = BB(), R.BuffBackWatch, R.BuffBackList, R.BuffBackUnlock
        local Under = K.Under
        local BOOL, STRING, NUMBER = K.BOOL, K.STRING, K.NUMBER
        local resettable = {}
        local function Setting(key, varType, label, set)
            local name = "buffBack" .. key:sub(1, 1):upper() .. key:sub(2)
            local s = K.Proxy(name, varType, label, bb.DEFAULTS[key], function() return bb.Get(key) end, set or function(v) bb.Set(key, v) end)
            -- the place and the Unlock Mode choice have their own controls; Reset keeps them
            if s and key ~= "x" and key ~= "y" and key ~= "unlockMode" then resettable[#resettable + 1] = { setting = s, default = bb.DEFAULTS[key] } end
            return s
        end
        local main
        local function Check(key, label, tip, isOn, why)
            return Under(K.Checkbox(Setting(key, BOOL, label, function(v) bb.Set(key, v and true or false) end), tip), main, isOn or On, why)
        end
        local function Pick(key, label, tip, choices, isOn, why)
            return Under(K.Dropdown(Setting(key, STRING, label), choices or function() return bb.CHOICES[key] end, tip), main, isOn or On, why)
        end
        local function Range(key, label, tip, isOn, why)
            local lim = bb.LIMITS[key]
            return Under(K.Slider(Setting(key, NUMBER, label, function(v) bb.Set(key, math.floor(v + 0.5)) end), lim[1], lim[2], tip), main, isOn or On, why)
        end
        local function Swatch(key, label, tip, isOn, why) return Under(K.Swatch(Setting(key, STRING, label), tip), main, isOn or On, why) end
        local function Label(key)
            for _, c in ipairs(bb.CHOICES[key] or {}) do if c[1] == bb.Get(key) then return c[2] end end
            return tostring(bb.Get(key))
        end

        -- 1. Who buffed you
        K.Card({
            title = "Who buffed you", icon = "resurrection",
            what = "When another player buffs you, their name appears in a short list with the buff's icon. Click their name to buff them back with something your class can give.",
            summary = function()
                if not On() then return "Off." end
                local parts = { ("%d seconds"):format(bb.Get("duration")), ("up to %d names"):format(bb.Get("maxRows")) }
                if bb.Get("anyBuff") then parts[#parts + 1] = "any helpful spell" end
                local paused = Wt.Paused()
                if paused then parts[#parts + 1] = PAUSED[paused] end
                return table.concat(parts, DOT)
            end,
            consequence = "A click casts only what the row shows, on the player it names, and only when you click; nothing is cast for you. In combat the list can't change, so new names wait and old ones dim until combat ends. Nothing about who buffed you is saved.",
            details = {
                { "What does a click cast?", "The first thing your class can give that they don't already have (when their buffs can be seen): a Mage's Arcane Intellect; a Priest's Power Word: Fortitude, Divine Spirit or Shadow Protection; a Druid's Mark of the Wild or Thorns; a Paladin's Blessing of Wisdom for those who use mana, Might for those who don't, or Kings; a Warlock's Unending Breath; a Warrior's Battle Shout when they are in your party. Spells for mana are never offered to someone without mana. The game picks the highest rank you know. The small icon on the right of a row is what a click casts; a faded one means there is nothing to give." },
                { "How does it target them?", "In your group the spell is cast on them by name, so it can only reach them. Outside your group they are targeted, the spell is cast and your own target is given back (or cleared, if you had none). If they are out of reach the game says so, and their row stays." },
                { "Which buffs count?", "The long buffs players give each other: Fortitude, Divine Spirit, Shadow Protection, Arcane Intellect, Mark of the Wild, Thorns, the Blessings, Unending Breath and the like, with their group versions. Heals, shields and your own buffs don't count, and neither do pets or NPCs. \"Count any helpful spell\" lists anything another player casts on you instead." },
                { "When does a name go?", "When its time runs out, when you right-click it, or when your buff lands on them after you clicked it. Buffed again by them, they move back to the top with the new buff." },
            },
        })
        main = K.Toggle("buffBack", "Show who buffed me",
            "On: when another player buffs you, their name appears in a short list for the time you choose below; click it to buff them back. Off: no list, and nothing is listened for. It reads only your own buffs and never sends anything (the thank-you emote below is separate and off by default).")
        K.Status("Right now",
            function()
                if not On() then return "Off" end
                local s = Wt.Snapshot()
                if s.paused then return "Paused" end
                return s.entries == 0 and "Waiting" or (s.entries == 1 and "1 name listed" or (s.entries .. " names listed"))
            end,
            function()
                if not On() then return nil end
                local paused = Wt.Paused()
                if paused then return "It is " .. PAUSED[paused] .. ": nothing is listed and nobody is thanked." end
                return "Read when this page is drawn."
            end,
            "Whether the list is listening where you are, and how many names it holds. Read when this page is drawn; it is not polled.",
            function() return (On() and not Wt.Paused()) and "ok" or "quiet" end)
        Range("duration", "Keep a name for (seconds)", "How long a name stays in the list after they buff you. Buffed again, the time starts over.")
        Range("maxRows", "Most names at once", "How many names the list holds. A new one pushes the oldest out. The list always takes this much room, so it doesn't move as names come and go.")
        Check("anyBuff", "Count any helpful spell", "Off (the default): only the long buffs players give each other. On: anything helpful another player casts on you, heals over time and shields included, which fills the list quickly in a group.")

        -- 2. Where it pauses
        K.Card({
            title = "Where it pauses", icon = "reminderWhen", switch = false,
            what = "Places where the list hides and listens for nothing, so it stays out of the way where buffs come all the time.",
            summary = function()
                local parts = {}
                if bb.Get("hideDungeon") then parts[#parts + 1] = "dungeons" end
                if bb.Get("hideRaid") then parts[#parts + 1] = "raids" end
                if bb.Get("hidePvP") then parts[#parts + 1] = "battlegrounds" end
                if bb.Get("hideResting") then parts[#parts + 1] = "cities and inns" end
                local text = #parts > 0 and ("Paused in " .. table.concat(parts, ", ")) or "Never paused"
                if bb.Get("hideCombat") then text = text .. DOT .. "hidden in combat" end
                return text
            end,
            consequence = "Paused means nothing is listed and nobody is thanked there; arriving there empties the list. Hidden in combat only hides the list while you fight: names still arrive and show when combat ends.",
        })
        Check("hideDungeon", "Pause in dungeons", "Five-player dungeons, which the game reports as party instances.")
        Check("hideRaid", "Pause in raids", "Raid instances. On by default: buffs there come from everyone at once.")
        Check("hidePvP", "Pause in battlegrounds and arenas", "On by default.")
        Check("hideResting", "Pause in cities and inns", "Wherever the game says you are resting: capital cities and inns.")
        Check("hideCombat", "Hide in combat", "Hides the list while you are in combat (the game does this, so it works in combat too), and shows it again afterwards.")

        -- 3. Thanking them
        K.Card({
            title = "Thanking them", icon = "notifications", switch = false,
            what = "Optionally, a friendly emote to the player who buffed you, a few seconds later, as if you had typed it.",
            summary = function()
                if not bb.Get("thank") then return "No emote." end
                local parts = { Label("thankEmote"), ("after about %d seconds"):format(bb.Get("thankDelay")) }
                if bb.Get("thankAfterReturn") then parts[#parts + 1] = "only once you buff them back" end
                return table.concat(parts, DOT)
            end,
            consequence = "The emote is seen by players near you, as /thank is. It is never sent in combat, while the game restricts chat, or when they are no longer around; the same player is thanked at most once every five minutes, and never two within ten seconds. This choice stays on this computer: a shared TwichUI setup never turns it on for someone.",
        })
        local thank = Check("thank", "Thank them with an emote", "Off by default. On: a few seconds after someone buffs you, you perform the emote below at them, as the game's own /thank does. It works for every class, whether or not you have anything to give back. It needs them still nearby (your target, mouseover, focus, group or a nameplate), else it is skipped.")
        local function ThankOn() return On() and bb.Get("thank") end
        local thankWhy = "Greyed out: turn on \"Thank them with an emote\" first."
        Under(K.Dropdown(Setting("thankEmote", STRING, "Emote"), function() return bb.CHOICES.thankEmote end,
            "Which of the game's emotes is performed at them."), thank, ThankOn, thankWhy)
        local delay = bb.LIMITS.thankDelay
        Under(K.Slider(Setting("thankDelay", NUMBER, "Wait before thanking (seconds)", function(v) bb.Set("thankDelay", math.floor(v + 0.5)) end), delay[1], delay[2],
            "How long after the buff lands the emote is performed (with \"Only after I buff them back\": after yours lands on them). Up to a second and a half more is added each time, so it isn't always the same."), thank, ThankOn, thankWhy)
        Under(K.Checkbox(Setting("thankAfterReturn", BOOL, "Only after I buff them back", function(v) bb.Set("thankAfterReturn", v and true or false) end), "Off: everyone who buffs you is thanked. On: nobody is thanked when their buff lands; the emote comes only after you click their row and your buff is seen landing on them, after the wait above. Someone you don't buff back (or buff some other way than their row) isn't thanked."),
            thank, ThankOn, thankWhy)

        -- 4. Appearance
        K.Card({
            title = "Appearance", icon = "appearance", switch = false,
            what = "How the list and each row look, and where the list sits.",
            summary = function()
                return table.concat({ Label("growth"), ("%d wide"):format(bb.Get("width")), ("%d%%"):format(bb.Get("scale")) }, DOT)
            end,
            consequence = "In combat the game doesn't let the list change, so a change waits until combat ends; opacity, colors and text change at once. Show a sample to see your changes and to drag the list into place.",
        })
        Under(K.Button("Sample", "Show or hide", function()
            local ok = L.Preview(not L.Previewing())
            if not ok then R.Print("%s", "Return the Favor: the sample can't be shown in combat.") end
        end, "Shows a list of made-up names where the list sits, drawn with your settings, so you can see them as you change them. Drag it to move the list (unless EllesmereUI's Unlock Mode is in charge of its place). Clicking it does nothing. It goes when combat starts or you click this again."), main, On)
        Pick("growth", "New names", "Downwards: the newest name is at the top. Upwards: the newest is at the bottom, for a list low on the screen.")
        Range("width", "Width", "How wide each row is.")
        Range("rowHeight", "Row height", "How tall each row is.")
        Range("spacing", "Space between rows", "The gap between two rows.")
        Range("iconSize", "Icon size", "The size of the buff's icon. It is kept inside the row.")
        Range("scale", "Scale (%)", "Makes the whole list bigger or smaller.")
        Range("opacity", "Opacity (%)", "How solid the rows are, background, border, icons and text together.")
        Under(K.Dropdown(Setting("font", STRING, "Font"), function() return MS.Fonts.Choices(bb.Get("font"), { { "default", "Game font (default)" } }) end,
            "The rows' typeface. Fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's are listed. A font that has gone is drawn with the game's own and stays chosen."), main, On)
        Range("textSize", "Text size", "The size of the name; the buff's name is drawn a little smaller.")
        Pick("outline", "Text outline", "Outline keeps the words readable over any scenery; Shadow is a soft dark edge; None leaves them bare.")
        local class = Check("classColor", "Color names by class", "Each name in its class's color (the game's, or your class color addon's). Off: the name color below.")
        Swatch("nameColor", "Name color", "The names' color while class colors are off.", function() return On() and not bb.Get("classColor") end,
            "Greyed out: names are in their class colors. Turn that off to choose one.")
        Check("showSpellName", "Show the buff's name", "The buff's name under the player's name. Off: just their name.")
        Swatch("textColor", "Buff name color", "The color of the buff's name.", function() return On() and bb.Get("showSpellName") end,
            "Greyed out: the buff's name is hidden.")
        Check("showReturn", "Show what a click casts", "A small icon at the right of each row: what a click gives back (faded when there is nothing to give).")
        for _, e in ipairs(K.Appearance(bb.Look, "buffBackRow", "row", nil, nil, nil, nil, main, On, {
            labels = { BgTexture = "Row background texture", BgColor = "Row background color", BgOpacity = "Row background opacity",
                BorderTexture = "Row border texture", BorderSize = "Row border thickness", BorderColor = "Row border color",
                BorderOpacity = "Row border opacity" } })) do
            resettable[#resettable + 1] = e
        end
        local unlockBase = "Move the list in EllesmereUI's Unlock Mode instead of by dragging its sample. A \"TwichUI Return the Favor\" mover appears there, and you drag it, nudge it, type its X and Y or anchor it to another element the way you do the rest of your interface. Turning this on keeps the list where it is. The place is still saved by TwichUI; EllesmereUI's anchor links are saved by EllesmereUI.\n\nOpen Unlock Mode with /unlock. It can't be opened in combat, and the list doesn't move then."
        local unlock = Under(K.Checkbox(Setting("unlockMode", BOOL, "Use EllesmereUI Unlock Mode", function(v) bb.Set("unlockMode", v and true or false) end), unlockBase), main, On)
        if unlock and unlock.GetTooltip ~= nil and U then
            local withParent = unlock.GetTooltip
            unlock.GetTooltip = function(self)
                local code = U.Status()
                local text = UNLOCK_STATUS[code] or { code }
                local color = (code == "active" and R.GREEN) or (code == "off" and R.GREY) or R.GOLD
                local tip = withParent(self) or unlockBase
                return tip .. "\n\nStatus: " .. color .. text[1] .. "|r" .. (text[2] and ("\n" .. text[2]) or "")
            end
        end
        Under(K.Button("Position", "Reset", function() bb.ResetPlace() end,
            "Puts the list back at its default place, left of and above the middle of the screen. Only its place changes. An anchor you made to another element in EllesmereUI's Unlock Mode is EllesmereUI's, and is removed there."), main, On)
        K.ResetButton("Return the Favor settings", resettable, function() bb.ResetSettings() end,
            "Puts the settings on this page back to their defaults, the rows' look included. The switch, the list's place and the Unlock Mode choice are kept.")
    end,
})
