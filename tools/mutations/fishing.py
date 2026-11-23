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
