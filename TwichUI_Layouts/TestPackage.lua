-- TwichUI Layouts: the developer test package (not an author layout)
-- A few settings that are easy to see and safe to take back, to exercise the whole pipeline in game: validate, plan,
-- apply, reload, verify, restore. Both parts go into profiles of their own, which Restore removes.
--   TwichUI (this character, at once): how long the zone card stays, the new-training card's look, and whether
--     smaller places within a zone get a card.
--   EllesmereUI (every character on the account, after a reload): where the minimap shows its coordinates, and that it
--     always shows them. The base is your own active EllesmereUI profile, exported with EllesmereUI's own export
--     (a developer package only: a real package ships the author's export strings).
-- The base and the variant both name arrivalHold, so the variant's value is the one that wins.

local R = TwichUI
local LY = R.Layouts

LY.TEST_PACKAGE = {
    format = 1, id = "twichui-layout-test", revision = 1, dev = true,
    title = "Layout pipeline test", made = "2026-10-26",
    requires = { ellesmereui = { min = "9.6.6", tested = "9.6.8" } },
    targets = { twichui = "Layout Test", ellesmereui = "TwichUI Layout Test" },
    layers = {
        base = {
            twichui = { groups = { notifications = { ui = { arrivalHold = "long", trainingStyle = "illustrated" } } } },
            ellesmereui = { base = { source = "active-profile" }, fields = { ["minimap.coordsMode"] = "always" } },
        },
        variants = {
            test = {
                twichui = { groups = { notifications = { modules = { arrivalSubzones = false }, ui = { arrivalHold = "longer" } } } },
                ellesmereui = { fields = { ["minimap.coordsPosition"] = "bottom" } },
            },
        },
    },
}
LY.TEST_VARIANT = "test"
