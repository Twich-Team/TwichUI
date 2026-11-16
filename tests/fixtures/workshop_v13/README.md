# Workshop 1.3 fixtures

Unmodified copies of the released TwichUI Workshop 1.3 sources, used by `tests/test_workshop_schema.lua` to prove that the **released**
code cannot damage a version-2 market database (market data foundation 2.0, milestone A2). Do not edit them, reformat them or "fix" them;
the test is only evidence while they are byte-for-byte what shipped.

- Source: git tag `v1.3.0` (commit `d09e6dcb29a4f9e3e3dbdba3fb7632c80043c810`), folder `TwichUI_Workshop/`.
- Files: `Data`, `Materials`, `Queue`, `History`, `Prices`, `Scan`, `Market` (`.lua`): the load order of the tag's `.toc` up to the files that
  read or write the saved prices. Only `Prices.lua` names `TwichUIWorkshopDB` in the whole release (`git grep TwichUIWorkshopDB v1.3.0`).
- Recreate and compare: `for f in Data Materials Queue History Prices Scan Market; do git show v1.3.0:TwichUI_Workshop/$f.lua | cmp - tests/fixtures/workshop_v13/$f.lua; done`
- Packaging: `.pkgmeta` ignores `tests`, so none of this ships.
