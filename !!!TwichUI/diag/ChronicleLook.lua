-- TwichUI: troubleshooting report, Chronicle appearance
-- Reads ChronicleAppearance.Snapshot(): whether the look is customised (not what it is set to), which
-- text roles had to fall back to the game's own font, whether LibSharedMedia and EllesmereUI are there,
-- what is held (text, controls, subscribers) and how many passes ran or were folded together. Never
-- Chronicle entries, notes or place names.

local R = TwichUI
local D = R.Diag

local function Customised()
    local ui = TwichUIDB and TwichUIDB.ui
    local function Has(t) return type(t) == "table" and next(t) ~= nil end
    return ui ~= nil and (Has(ui.chronicleLook) or Has(ui.chronicleAppearance))
end

local function Snapshot()
    local A = R.ChronicleAppearance
    if not (A and A.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = A.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("look: %s; customised: %s", s.look and "ready" or "not made", D.Flag(Customised()))
    Line("media: LibSharedMedia %s, EllesmereUI %s", LibStub and LibStub("LibSharedMedia-3.0", true) and "available" or "not available",
        R.Borders and R.Borders.Ellesmere() and "available" or "not available")
    Line("fonts: %s", #s.fallbacks > 0 and ("fell back to the game's own for " .. table.concat(s.fallbacks, ", ")) or "as chosen")
    Line("holds: %d text strings, %d edit boxes, %d controls, %d listeners", s.texts, s.edits, s.widgets, s.subscribers)
    if s.fonts then Line("font list: %d names kept, %d files checked", s.fonts.listed, s.fonts.probed) end
    Line("work: %d passes, %d changes, %d folded into another, %d dropped unused, %d fonts set; pass waiting: %s",
        s.applies, s.requests, s.coalesced, s.cancelled, s.styled, D.Flag(s.waiting))
    return {
        configured = nil, initialized = D.When(true, s.look), status = s.look and "ready" or "unavailable",
        reason = (not s.look) and "no-look" or nil, lines = lines,
        limits = {
            "Only the Chronicle window, its note editor and date picker follow this; the zone arrival and Welcome Back cards do not.",
            "Whether a font or texture looks right can only be seen in the game.",
        },
    }
end

D.Register("chronicleLook", { title = "Chronicle appearance", order = 55, snapshot = Snapshot })
