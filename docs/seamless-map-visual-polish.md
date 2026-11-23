# Seamless map visual polish

## Accepted starting point

PR [#138](https://github.com/Twich-Team/TwichUI/pull/138) merged into `main` as
`7fbebd3b6ddd2143d6445b0f1eead58ca487023e`. Required PR verification passed
340 modules / zero failures, as did Market regressions; the automatic main
verification also passed. The separate local complete run retained the documented
Welcome Back baseline failure (339 pass / one failure at
`test_welcome_back.lua:84`); its code and assertions remain unchanged.
No publication or deployment occurred.

`feature/seamless-map-visual-polish` starts at that exact merged main. Navigation,
terrain/interior budgets, cave/city/NPC behavior, diagnostics, the real-art lab
and collector are preserved. The accepted `map-regional-after` and earlier
reference galleries remain untouched.

## Matching cameras

`polish-v1` adds ten fixed production-Lua cameras at 4/8/12/24: Eastern Kingdoms,
Kalimdor, central Eastern Kingdoms, the southern boundary, Badlands,
Elwynn/Westfall/Duskwood, Stranglethorn, Booty Bay, Tirisfal and Undercity.
Requested and actual centers/zoom are exported separately. These are repeatable
presets, not recovered player screenshots. Existing catalogs are unchanged.

```sh
python3 tools/maplab/run.py --client-bundle /private/part-01.zip \
  --client-bundle /private/part-02.zip --client-bundle /private/part-03.zip \
  --scenario-set polish-v1 --output test-output/map-polish-review --strict
```

Private baseline: `test-output/map-polish/baseline/index.html`, built from the
accepted production sources with Forever 1.60.1.71037 artwork and the previously
validated same-build legacy supplement. Lua export: 1.713402 s; composition:
165.055305 s. Offline wall times do not measure native CPU/GPU performance.
The state records all eight production-renderer source hashes.

36 of 40 views have complete visible artwork. Eastern overview, Kalimdor,
Badlands and Stranglethorn at 24 are partial for 44 unique uncollected textures.
The lab retains explicit placeholders/findings; these are missing lab inputs,
not evidence of missing installed-client artwork. The generated private
`asset-request.json` identifies inputs for a future refresh. No additional input
is required to investigate the complete regional views.

All source artwork, derived studies and comparison screenshots remain ignored
private files. No Blizzard-derived pixels are packaged or committed.
