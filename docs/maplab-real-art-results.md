# First real-artwork inspection loop

Private user input supplied actual Forever **1.60.1.71037**, product **wowf**:
52 map records, 1,812 candidate textures, 1,812 present and zero collector misses.
All three ZIP parts passed bounded import and SHA-256 verification. The reviewed
table layouts remain compatible with this newer build. These are client-table
API inputs, not captured native zone/phase behavior or native screenshots.

## Render, inspect, fix, rerender

The existing production Lua pipeline generated twelve real-art views: Booty Bay,
Undercity and the Elwynn/Westfall border region at zoom 12/24/36/48. Both before
and after runs passed `--strict`, with zero missing selected artwork. An extra
Stormwind view checked the surface-city guard using the same supplied input.

The primary agent directly inspected Booty Bay 48, Undercity 24/48, border 48,
opacity experiments, the native adjacent tile pair, and the resulting after
images. An independent agent inspected Undercity and border 24/36/48. Images
were inspected using image tools; synthetic geometry checks were not substituted
for this inspection.

| Observed defect | Production cause | Implemented correction | Offline retest |
|---|---|---|---|
| Giant blurred painting lettering/hatching over Booty Bay water and border terrain at deep zoom | Detail stopped at 70% opacity | Preserve the intermediate blend, then crossfade toward the selected maximum from zoom 36–48; default maximum now 100% | Deep outdoor lettering disappears with complete native detail coverage; no extra tile allocations |
| Large surrounding-zone UNDERCITY banner shows through the central city street plan at zoom 24 | City intro waits for fit×0.35–0.7 | City plan intro now fit×0.2–0.4 | Central plan becomes readable; city alpha at 24 rises from approximately 0.45977 to 1 |

Private opacity experiments compared 0.7, 0.85 and 1 using identical source
geometry. The full-opacity terrain covered 100% of the tested deep outdoor
viewports; it removed the intrusive glyph/hatching layer most clearly. The
accepted after images were then regenerated through production Lua, rather
than presented as postprocessed experiments.

Terrain alpha at 24 remains 0.109375, at 36 remains 0.7, and at 48 changes from
0.7 to 1 for the new default. Booty Bay 12/24/36 and border 24/36 are pixel-identical
in this comparison. Surface-city plans keep the old central 0.7 blend with a
spatially smooth boundary; Stormwind 48 was rendered/inspected with alpha 0.7
and zero missing textures. Explicit saved strengths such as 50 or 70 remain
the selected maximum, with no profile migration or forced overwrite. Choose
100 in World map → Detail strength if a profile explicitly saved the old 70.

Underground city ordering, WMO crop/rotation and its 0.5 picture mix remain
unchanged. Native Undercity circles/roads broadly align with the plan in these
offline views; native alignment/floor acceptance remains outstanding. The
surface-city guard shares the actual city intro calculation, avoiding dependence
on renderer listener order.

## Reproduction and private artifacts

```sh
source /workspace/twichui-env/activate.sh
python3 tools/maplab/run.py \
  --client-bundle /private/TwichUI-map-art-01.zip \
  --client-bundle /private/TwichUI-map-art-02.zip \
  --client-bundle /private/TwichUI-map-art-03.zip \
  --baseline test-output/maplab-real-before \
  --output test-output/maplab-real-after --strict
```

Do the initial run into `maplab-real-before` without `--baseline` before changing
code. Artifact folders from this run are local/ignored, never addon/repository
release inputs:

- `test-output/maplab-real-before/index.html`: twelve initial actual-art views.
- `test-output/maplab-real-after/index.html`: twelve production rerenders,
  layer overlays, opaque difference images and structured state/metrics.
- `test-output/maplab-real-after/real-art-before-after.png`: inspected Booty Bay
  48 / Undercity 24 comparison sheet, before on the left and after on the right.
- `test-output/maplab-real-validated/index.html`: final maintained-importer run;
  all twelve images are pixel-identical to the accepted after gallery.
- `test-output/maplab-real-city-safeguard/index.html`: Stormwind guard view.
- `test-output/maplab-real-experiments/`: explicitly labeled opacity experiments.

The initial full gallery took 71.817 s (Lua export 0.706 s); the after gallery
with differences took 67.303 s (Lua export 0.397 s). These are offline compositor
and startup/cache timings, not a controlled performance speedup or client frame
time. Stormwind's single-view compositor took 3.569 s.

## Remaining visible limitations

- A native terrain brightness boundary near Booty Bay remains visible at full
  opacity. Directly placing source tiles 204423/204463 side by side shows the
  boundary in their pixels, while shoreline/road geometry is contiguous. This
  does not establish how native minimap shaders present it. No geometry was
  distorted to hide it.
- A remnant of the surrounding banner outside Undercity's own painted rectangle
  remains. Earlier intro fixes the central plan, not the missing semantic city
  cuts. Territory/land/city/ocean masks are still separate fidelity work.
- The border preset is a map-rectangle overlap region. Its adapter can choose
  Duskwood as the host; this is not native zone-shape validation. Production world
  placement remains shared across hosts, but native context acceptance is needed.
- Mixed surface-city plan/native geometry can differ stylistically. This loop
  does not establish every city's alignment, automatic floor selection, shader
  filtering, protected combat behavior or third-party marker compatibility.

The pinned OpenMap source supports staged deep detail and earlier city takeover.
No processed OpenMap artwork was imported, and no comparable complete OpenMap
render was available; OpenMap-level fidelity is not claimed.

## Performance, budgets and preprocessing evidence

The seeded 4,000-operation course still creates zero warmed terrain textures,
with peak 24 active; terrain remains capped at 80 and each interior set at 256.
All 250 numeric areas / 1,906 pictures validate, with peak current-record pool
217. No background polling/profiler was added. Existing map scopes account for
the changed view-driven work; support snapshots expose both fade ranges.

Three fixture CPU runs before/after ranged widely: before 3.1731/1.9849/1.6882 s,
after 3.3345/1.7099/1.8355 s (medians 1.9849/1.8355). The ranges overlap, so no
reliable speedup is asserted. These are offline Lua/fixture costs, not native
CPU/GPU, streaming or cold-client measurements.

The existing preprocessing helper also ran privately on actual native tile
204423. Its 512×512 PNG was 168,477 bytes; 64×64 LOD was 6,421 bytes, 16×16 LOD
628 bytes, and a guttered 66×66 result 6,489 bytes. This proves actual source
decoding/downsampling, not a production atlas or GPU format. Its alpha was
uniformly 255: source alpha alone cannot derive a land/ocean mask for that tile.
No native or derived artwork was committed or added to addon packaging; rights,
semantic masks and production format compatibility remain gates. Production
rendering architecture is unchanged.

Focused production checks pass: map diagnostics and 4,000-operation regression
course, all local numeric data, Lua syntax and the settings contract. The four
contract fixture changes are only the intentional detail default and tooltip.
Final extraction/integration verification:

```sh
source /workspace/twichui-env/activate.sh
python3 -B tests/test_maplab_extract.py  # 16 passed
python3 -B tests/test_maplab_client.py   # 16 passed; Lua activated
python3 -B tests/test_maplab.py          # 18 passed
./tests/run.sh feature navigation --profile cloud --jobs 2
```

The feature gate passed **99 test modules, zero failures**, syntax (307 Lua
files plus runner scripts) and simulator smoke in **108.774 s**; source
fingerprints remained unchanged. This cloud profile does not satisfy native or
local milestone/release acceptance. The final `--client-bundle ... --strict`
run passed twelve scenes with zero missing assets in **91.085 s** (Lua export
0.495 s), concurrently with the gate. It fully header/hash-validated all 1,812
legacy payloads (106,728,632 bytes), retained explicit legacy limitations, and
produced zero pixel differences from the accepted after gallery. New schema-2
collection/import/update/recovery uses owned fixture tests; a complete native
gaming-PC run of the new incremental collector remains untested.

The prior full suite on `70bd271` remains **324 passed / 1 failed** (668.519 s).
Its Welcome Back date assertion at `tests/test_welcome_back.lua:84` is unrelated
and untouched. Original 322-pass/1-failure baseline and untouched reproduction
evidence remain preserved. The full suite was not repeated after these focused
map/tooling changes; the affected gate above was rerun.
