"""Fishing estimates: provenance, missing values, generation and market identity."""
SUITE = {"copy_dirs": ("TwichUI_Fishing", "TwichUI_Settings", "TwichUI_Workshop", "TwichUI_TestLab", "TwichUI_Diagnostics"), "targets": ("TwichUI_Fishing/",), "broad_tests": ("test_fishing_containers.lua",)}
MUTATIONS = []
def m(name, find, replace):
    MUTATIONS.append(dict(id="fishing.economy." + name, file="TwichUI_Fishing/Economy.lua", find=find,
        replace=replace, why=name.replace("-", " "), tests=("test_fishing_economy.lua",), smoke=True, expect="killed"))
m("opened-shell-double-count", "math.max(0, (lot.unopened or 0) - (lot.partial or 0))", "lot.caught or 0")
m("missing-becomes-zero", "out.total = out.priced > 0 and out.known or nil", "out.total = out.known")
m("stale-generation", "p.Generation(), m and m.key", '"fixed", m and m.key')
m("mixed-market-identity", 'tostring(m and m.realm), tostring(m and m.side)', '"realm", "side"')

MUTATIONS.append(dict(id="fishing.economy.shared-item-display", file="TwichUI_Fishing/EconomyPresent.lua",
    find="items = Values(v.direct)", replace="items = Values(v.contents)",
    why="a directly caught fish and the same fish in container contents display the wrong quantity value",
    tests=("test_fishing_economy.lua",), smoke=True, expect="killed"))

MUTATIONS.append(dict(id="fishing.economy.partial-lot-marker", file="TwichUI_Fishing/Containers.lua",
    find="    Ses.ContainerOpened(lot.sid, lot.item, lot.zone)",
    replace="    lot.partial = nil\n    Ses.ContainerOpened(lot.sid, lot.item, lot.zone)",
    why="finishing one shell clears uncertainty for other partially looted shells in the same lot",
    tests=("test_fishing_partial_lots.lua",), smoke=True, expect="killed"))

MUTATIONS.append(dict(id="fishing.loot.preclose-confirmation", file="TwichUI_Fishing/Loot.lua",
    find="if #held == 0 and not Lo.Open() then return end",
    replace="if #held == 0 then return end",
    why="discarding self-loot confirmation before close loses native auto-looted clam contents and their value",
    tests=("test_fishing_native_loot.lua",), smoke=True, expect="killed"))

MUTATIONS.append(dict(id="fishing.loot.external-open-reservation", file="TwichUI_Fishing/Containers.lua",
    find="C_Timer.After(0, Observe)", replace="C_Timer.After(3, Observe)",
    why="waiting beyond the next external clam open loses the per-window shell consumption and provenance",
    tests=("test_fishing_external_containers.lua",), smoke=True, expect="killed"))

MUTATIONS.append(dict(id="fishing.loot.external-window-boundary", file="TwichUI_Fishing/Containers.lua",
    find="if not attr.consumed then attr.expired = true end",
    replace="if false then attr.expired = true end",
    why="an unrelated older item window steals a later clam's bag transition and fishing provenance",
    tests=("test_fishing_external_containers.lua",), smoke=True, expect="killed"))
