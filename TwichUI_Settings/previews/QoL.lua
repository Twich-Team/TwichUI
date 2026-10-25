-- TwichUI Settings: Quality of life previews (Previews.lua)
-- Drawings of what each convenience does, with sample names and places, for the cards on the Quality of life
-- page. They read the rules as set (who may summon you, how long a wait is) through the settings' own labels, and
-- call nothing in qol/: no summon is accepted, no resurrection, release or duel answered. Each says "Sample".

local R = TwichUI
local K = R.SettingsKit
local Wg = R.SettingsWidgets
local P = R.SettingsPreviews
local pal = Wg.pal

-- A setting's value as its control shows it ("Friends, guild and group members", "3 seconds"), read only.
local function Label(variable)
    local s = K.variables["TWICHUI_" .. variable]
    return s and K.ValueText(s) or ""
end
local function Get(key) return R.QoL and R.QoL.Get(key) end
local function On(key) return R:Enabled(key) and true or false end

local function Line(parent, kind, x, y, w)
    local fs = Wg.Text(parent, kind)
    fs:SetPoint("TOPLEFT", x, y)
    if w then fs:SetWidth(w); fs:SetWordWrap(true) end
    return fs
end

-- Who the sample summoner or challenger is, for a "from" rule: someone the rule lets through (or, for duels
-- with no exceptions, someone it doesn't).
local WHO = {
    known = "a member of your guild", group = "in your group", anyone = "a stranger",
    friendsGuild = "a member of your guild", friends = "on your friends list", nobody = "on your friends list",
}

-- How much faster than real time a wait is drawn so one play stays near three seconds. The caption says so.
local function Pace(wait, room)
    if wait <= room then return 1 end
    return wait / room
end

---------------------------------------------------------------------------
-- Accept summons: an offer, its wait counting down, accepted
---------------------------------------------------------------------------
local SUMMON_ROOM = 2.2   -- seconds of a play given to the wait

P.Register("qol.summons", {
    height = 84,
    Sample = function()
        return { on = On("qolSummons"), from = Get("summonsFrom") or "known", fromText = Label("qolSummonsFrom"),
            wait = Get("summonsWait") or 3, waitText = Label("qolSummonsWait") }
    end,
    Duration = function(s) return 0.4 + math.min(s.wait, SUMMON_ROOM) + 1.2 end,
    Create = function(stage)
        local sc = {}
        sc.popup = P.Popup(stage, 290, 64)
        sc.popup:SetPoint("TOPLEFT", 12, -10)
        sc.text = Line(sc.popup, "small", 10, -8, 270)
        sc.count = Line(sc.popup, "meta", 10, -24, 270)
        sc.accept = P.FakeButton(sc.popup, "Accept", 70)
        sc.accept:SetPoint("BOTTOMLEFT", 10, 6)
        sc.decline = P.FakeButton(sc.popup, "Decline", 70)
        sc.decline:SetPoint("LEFT", sc.accept, "RIGHT", 8, 0)
        sc.who = Line(stage, "small", 318, -14, 240)
        sc.rule = Line(stage, "meta", 318, -48, 240)
        return sc
    end,
    Reset = function(sc, s)
        sc.popup:SetAlpha(1)
        sc.text:SetText("Aelric wants to summon you to Ironforge.")
        Wg.Color(sc.text, pal.text)
        sc.count:SetText(s.wait == 0 and "Accepted as it arrives." or ("Accepting in %d..."):format(s.wait))
        Wg.Color(sc.count, pal.stone)
        sc.accept:Show(); sc.decline:Show()
        sc.accept:SetLit(false); sc.decline:SetLit(false)
        sc.who:SetText("Aelric is " .. (WHO[s.from] or WHO.known) .. ".")
        sc.rule:SetText("Accepts summons from: " .. s.fromText)
    end,
    Update = function(sc, t, s)
        sc.popup:SetAlpha(0.25 + 0.75 * P.Ramp(t, 0, 0.4))
        local shown = math.min(s.wait, SUMMON_ROOM)
        local into = math.max(0, t - 0.4) * Pace(s.wait, SUMMON_ROOM)
        if t < 0.4 + shown then
            local left = math.max(1, math.ceil(s.wait - into))
            sc.count:SetText(("Accepting in %d..."):format(left))
            Wg.Color(sc.count, pal.tealHi)
        else
            sc.accept:SetLit(true)
            sc.count:SetText("Accepting...")
        end
    end,
    Final = function(sc, s)
        sc.popup:SetAlpha(1)
        sc.accept:Hide(); sc.decline:Hide()
        sc.text:SetText("Summon accepted.")
        Wg.Color(sc.text, pal.tealHi)
        sc.count:SetText("You would arrive beside Aelric in Ironforge.")
        Wg.Color(sc.count, pal.text)
    end,
    Caption = function(s)
        local pace = s.wait > SUMMON_ROOM and " (The wait is shown faster than it runs.)" or ""
        return ("A summon from someone the rule allows waits %s with the game's own pop-up up, so you can still decline, then is accepted. Anyone else's summon is left for you to answer.%s"):format(
            s.wait == 0 and "no time" or s.waitText:lower(), pace)
    end,
})

---------------------------------------------------------------------------
-- Accept resurrection: a gray portrait and an offer, accepted, the portrait restored
---------------------------------------------------------------------------
P.Register("qol.resurrect", {
    height = 84,
    duration = 2.6,
    Sample = function() return { combat = On("qolResurrectCombat") } end,
    Create = function(stage)
        local sc = {}
        sc.gray = P.Portrait(stage, 52, true)
        sc.gray:SetPoint("TOPLEFT", 14, -16)
        sc.color = P.Portrait(stage, 52, false)
        sc.color:SetPoint("TOPLEFT", 14, -16)
        sc.popup = P.Popup(stage, 250, 52)
        sc.popup:SetPoint("TOPLEFT", 80, -16)
        sc.text = Line(sc.popup, "small", 10, -8, 230)
        sc.state = Line(sc.popup, "meta", 10, -26, 230)
        sc.ordinary = Line(stage, "meta", 346, -16, 220)
        sc.combat = Line(stage, "meta", 346, -42, 220)
        return sc
    end,
    Reset = function(sc, s)
        sc.gray:SetAlpha(1); sc.color:SetAlpha(0)
        sc.popup:SetAlpha(1)
        sc.text:SetText("Brother Anselm wants to resurrect you.")
        Wg.Color(sc.text, pal.text)
        sc.state:SetText("You are dead.")
        Wg.Color(sc.state, pal.stone)
        sc.ordinary:SetText("Out of combat: accepted for you.")
        sc.combat:SetText(s.combat and "In combat, from your group: accepted too."
            or "In combat, from your group: waits for you to accept.")
    end,
    Update = function(sc, t)
        sc.popup:SetAlpha(0.25 + 0.75 * P.Ramp(t, 0, 0.4))
        if t >= 0.9 then
            sc.state:SetText("Accepting...")
            Wg.Color(sc.state, pal.tealHi)
        end
        local f = P.Ramp(t, 1.3, 2.1)
        sc.color:SetAlpha(f)
        sc.gray:SetAlpha(1 - f)
    end,
    Final = function(sc)
        sc.color:SetAlpha(1); sc.gray:SetAlpha(0)
        sc.text:SetText("Resurrection accepted.")
        Wg.Color(sc.text, pal.tealHi)
        sc.state:SetText("You rise with the health the spell gives.")
        Wg.Color(sc.state, pal.text)
    end,
    Caption = function(s)
        return "An offer from another player is accepted once the game's own wait is over. "
            .. (s.combat and "Combat resurrections from your group are accepted too, so you may rise into a fight still going."
                or "Combat resurrections from your group wait for you to accept them.")
            .. " An offer with resurrection sickness is always left to you."
    end,
})

---------------------------------------------------------------------------
-- Release in battlegrounds: a body, the release wait, the spirit
---------------------------------------------------------------------------
local RELEASE_ROOM = 1.8

P.Register("qol.release", {
    height = 84,
    Sample = function() return { wait = Get("releaseWait") or 2, waitText = Label("qolReleaseWait") } end,
    Duration = function(s) return 0.4 + math.min(s.wait, RELEASE_ROOM) + 1.2 end,
    Create = function(stage)
        local sc = {}
        sc.body = P.Portrait(stage, 52, false)
        sc.body:SetPoint("TOPLEFT", 14, -16)
        sc.ghost = P.Portrait(stage, 52, true)
        sc.ghost:SetPoint("TOPLEFT", 14, -16)
        sc.place = Line(stage, "meta", 80, -14, 260)
        sc.button = P.FakeButton(stage, "Release Spirit", 110)
        sc.button:SetPoint("TOPLEFT", 80, -32)
        sc.state = Line(stage, "small", 80, -56, 260)
        sc.shift = Line(stage, "meta", 346, -16, 220)
        sc.scope = Line(stage, "meta", 346, -42, 220)
        return sc
    end,
    Reset = function(sc, s)
        sc.body:SetAlpha(1); sc.body:SetVertexColor(0.55, 0.5, 0.48, 1)
        sc.ghost:SetAlpha(0); sc.ghost:SetVertexColor(pal.tealHi[1], pal.tealHi[2], pal.tealHi[3], 1)
        sc.place:SetText("Warsong Gulch (a battleground)")
        sc.button:Show(); sc.button:SetLit(false)
        sc.state:SetText(s.wait == 0 and "Releases as you die." or ("Releasing in %d..."):format(s.wait))
        Wg.Color(sc.state, pal.stone)
        sc.shift:SetText("Hold Shift as the wait ends to keep your body.")
        sc.scope:SetText("Never in dungeons, raids, arenas or the open world.")
    end,
    Update = function(sc, t, s)
        local shown = math.min(s.wait, RELEASE_ROOM)
        local into = math.max(0, t - 0.4) * Pace(s.wait, RELEASE_ROOM)
        if t < 0.4 + shown then
            sc.state:SetText(("Releasing in %d..."):format(math.max(1, math.ceil(s.wait - into))))
            Wg.Color(sc.state, pal.tealHi)
        else
            sc.button:SetLit(true)
            local f = P.Ramp(t, 0.4 + shown, 0.4 + shown + 0.8)
            sc.ghost:SetAlpha(0.8 * f)
            sc.body:SetAlpha(1 - f)
        end
    end,
    Final = function(sc)
        sc.body:SetAlpha(0); sc.ghost:SetAlpha(0.8)
        sc.button:Hide()
        sc.state:SetText("Released: you are a spirit at the graveyard.")
        Wg.Color(sc.state, pal.text)
    end,
    Caption = function(s)
        local pace = s.wait > RELEASE_ROOM and " (The wait is shown faster than it runs.)" or ""
        return ("After you die in a battleground your spirit is released %s. A resurrection offered during the wait, a soulstone, or holding Shift keeps your body.%s"):format(
            s.wait == 0 and "at once" or s.waitText:lower() .. " later", pace)
    end,
})

---------------------------------------------------------------------------
-- Decline duel requests: a request, declined (or left for you, for someone you allow)
---------------------------------------------------------------------------
P.Register("qol.duels", {
    height = 84,
    duration = 2.4,
    Sample = function()
        return { from = Get("duelsFrom") or "known", fromText = Label("qolDuelsFrom"), death = On("qolDuelsToDeath") }
    end,
    Create = function(stage)
        local sc = {}
        sc.popup = P.Popup(stage, 290, 60)
        sc.popup:SetPoint("TOPLEFT", 12, -10)
        sc.text = Line(sc.popup, "small", 10, -8, 270)
        sc.state = Line(sc.popup, "meta", 10, -24, 270)
        sc.accept = P.FakeButton(sc.popup, "Accept", 70)
        sc.accept:SetPoint("BOTTOMLEFT", 10, 6)
        sc.decline = P.FakeButton(sc.popup, "Decline", 70)
        sc.decline:SetPoint("LEFT", sc.accept, "RIGHT", 8, 0)
        sc.allowed = Line(stage, "meta", 318, -14, 240)
        sc.death = Line(stage, "meta", 318, -48, 240)
        return sc
    end,
    Reset = function(sc, s)
        sc.popup:SetAlpha(1)
        sc.text:SetText("Garrick challenges you to a duel.")
        Wg.Color(sc.text, pal.text)
        sc.state:SetText("Garrick is a stranger.")
        Wg.Color(sc.state, pal.stone)
        sc.accept:Show(); sc.decline:Show()
        sc.accept:SetLit(false); sc.decline:SetLit(false)
        sc.allowed:SetText(s.from == "nobody" and "Still allowed: nobody. Every request is declined."
            or ("Still allowed: " .. s.fromText:lower() .. ". Their requests reach you as usual."))
        sc.death:SetText(s.death and "Duels to the death: declined too." or "Duels to the death: still reach you.")
    end,
    Update = function(sc, t)
        sc.popup:SetAlpha(0.25 + 0.75 * P.Ramp(t, 0, 0.3))
        if t >= 0.9 then sc.decline:SetLit(true) end
        if t >= 1.2 then sc.popup:SetAlpha(1 - 0.5 * P.Ramp(t, 1.2, 1.8)) end
    end,
    Final = function(sc)
        sc.popup:SetAlpha(0.6)
        sc.accept:Hide(); sc.decline:Hide()
        sc.text:SetText("Duel declined.")
        Wg.Color(sc.text, pal.tealHi)
        sc.state:SetText("Garrick sees it declined. Nothing is said in chat.")
        Wg.Color(sc.state, pal.text)
    end,
    Caption = function(s)
        return "A request from someone outside your exceptions is declined as it arrives, as if you had pressed Decline. "
            .. (s.from == "nobody" and "With no exceptions, every request is declined."
                or ("Requests from " .. s.fromText:lower() .. " still reach you."))
    end,
})

---------------------------------------------------------------------------
-- Quick Keybind button: where it sits in the Game Menu (a still picture: nothing to play)
---------------------------------------------------------------------------
P.Register("qol.quickKeybind", {
    height = 84,
    static = true,
    Create = function(stage)
        local sc = {}
        sc.menu = P.Popup(stage, 150, 70)
        sc.menu:SetPoint("TOPLEFT", 12, -7)
        local y = -6
        for _, label in ipairs({ "...", "Macros", "Quick Keybind", "..." }) do
            local fs = Line(sc.menu, label == "..." and "meta" or "small", 0, y)
            fs:SetWidth(150)
            fs:SetJustifyH("CENTER")
            fs:SetText(label)
            if label == "Quick Keybind" then
                Wg.Color(fs, pal.tealHi)
                local mark = Wg.Solid(sc.menu, "ARTWORK", pal.teal, 0.18)
                mark:SetPoint("TOPLEFT", 6, y + 2)
                mark:SetSize(138, 15)
            end
            y = y - 15
        end
        sc.note = Line(stage, "meta", 180, -14, 380)
        sc.note:SetText("The Game Menu (Escape) gains a Quick Keybind button below Macros. It opens the game's own Quick Keybind Mode.")
        return sc
    end,
    Caption = function()
        return "Entering Quick Keybind Mode changes no bindings; it can't be opened in combat, and the button is dimmed until combat ends."
    end,
})
