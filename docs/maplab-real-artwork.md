# Reusable real-artwork collection for Map Lab

Map Lab now has a permanent **collect → validate → update → render → inspect**
workflow. The initial private Forever 1.60.1.71037 input supplied 1,812 of 1,812
candidate textures. Production Lua rendered twelve before and twelve after
views with zero missing textures; direct image inspection led to a supported
runtime visual correction. See [the real-art results](maplab-real-art-results.md)
for images/evidence, changes and native-client limitations. Those private assets
and generated screenshots stay outside Git and release packages.

The reusable collector replaces the earlier one-shot handoff. It does not need
an in-game report, game launch, login, Lua, Pillow or third-party Python packages
on the gaming PC. **Python 3.10+ standard library is sufficient.**

## Player/developer workflow

From a current checkout or extracted source kit:

```powershell
py -3 tools/maplab/collect.py --wow "D:\Games\World of Warcraft" --output "test-output\maplab-client-input"
```

WSL/Linux equivalent:

```sh
python3 tools/maplab/collect.py --wow "/mnt/d/Games/World of Warcraft" --output test-output/maplab-client-input
```

Use the actual installed root or `_forever_` folder. The tool checks two nearby
parents and reads the installed product/active build from `.build.info`.
An ambiguous installation lists valid `--product` choices. Do not manufacture
a product ID from a folder name. Windows users can also double-click
`Collect-Map-Art.cmd`, which passes optional command-line arguments through and
falls back from the Python launcher to `python` when appropriate. Omitting
`--wow` opens a folder picker; explicit paths work without a graphical session.
Native Windows launcher/picker behavior still requires owner acceptance.

Run the **same command and destination** after a client update. The collector
rereads current tables and minimap indexes, verifies source identities and
retained payloads, and reports added, changed, removed, reused and freshly read
assets. It prints the exact private ZIP paths to share; all numbered parts are
required. Nothing uploads automatically. Existing explicit `.zip` output remains
supported for one-shot transfers and refuses existing output names.

The recommended output directory contains:

| Path | Meaning |
| --- | --- |
| `versions/<build>-<digest>/` | Immutable validated input, raw artwork, manifest and transfer ZIPs |
| `current.json` | Latest successful version; retained across a partial or failed update |
| `latest.json` | Latest published result, including an explicitly partial version |
| `latest-update.json` | Concise build/asset/cache diff |

A source texture is reused only when its current CASC CKey matches the saved
CKey, product and reader locale selection are compatible, and the cached file's
SHA-256/header validation succeeds. **Unknown/missing source identity forces a
fresh archive read.** Build changes do not imply unchanged bytes; file IDs alone
never authorize reuse. Removed candidates are excluded from the new version.
Corrupt caches are ignored; repair creates a separate immutable version rather
than overwriting the old one. Valid ZIP CRC alone is insufficient: cached ZIP
member sets and exact metadata/asset SHA-256 must match the validated version.

New artifacts are staged privately and validated before atomic directory
publication. Pointer JSON is written completely before replacement. An
interruption/failure preserves the previous successful pointer and artifacts;
a partial version can be inspected through `latest.json` without promotion to
`current.json`. ZIP files use exclusive same-filesystem hard-link publication,
so unsupported/network filesystems fail without replacing prior outputs. Local
NTFS/ext4 directories are the intended storage; native Windows remains untested
here. Old versions remain available for comparisons and can be removed manually
when no longer needed. No automatic cache cleanup deletes a baseline.

The default cache is under existing ignored/excluded `test-output/`. Other
explicit destinations must also remain private and outside addon packages and
the game installation. The script reads local CASC only: no game writes,
WTF/account/SavedVariables reads, CDN/network access, decryption, credentials,
injection, process-memory access, gameplay automation or automatic uploads.

## Versioned manifest and validation scope

`client.json` stays at input schema 1, preserving the existing production-Lua
adapter. New `assets/manifest.json` uses **schema 2**, kind
`twichui-maplab-artwork-bundle`, and records:

- Actual client build/product, collector tool name/version and protocol schema.
- Truthful locale provenance: selected `enUS-compatible-root-blocks`, native
  `clientLocale: "unknown"`. The reader does not implement selectable locales
  or observe the native client's chosen language.
- SHA-256 binding of the canonical complete client metadata; source table/numeric
  data hashes remain in that bound metadata.
- Sorted candidate IDs and exact available/missing accounting.
- Each file-data ID, raw/source SHA-256, CASC CKey where available, declared
  BLP/DDS header dimensions/format, build and provenance.
- Extraction settings/limits, missing/encrypted/unsupported inputs and a
  recomputed `success`, `partial` or `failure` validation result.

Header validation bounds each texture and its declared mip data; impossible
short DXT/palette/BGRA or DDS payloads fail. Unknown containers/unsupported DDS
DX10 layouts fail instead of being guessed. This verifies raw header structure,
hash identity and accounting, **not successful pixel decoding or native visual
acceptance**. The receiving lab separately decodes actual pixels and verifies
selected layers. Unknown future table layouts require a reviewed tool update;
users should not edit schema constants to force collection.

Schema-1 private inputs remain importable. Their hashes, build consistency,
candidate accounting where present and every raw texture header are checked,
while missing newer CKey/header/settings/locale provenance is explicitly labeled
legacy. A complete legacy raster set is not silently upgraded to schema-2
provenance. Shared `tools/maplab/bundle.py` defines validation for collector and
importer. Partial input must never be described as complete real-art coverage.

Eight map tables are read with reviewed layout and table hashes pinned to
[WoWDBDefs `3a7954cf`](https://github.com/wowdev/WoWDBDefs/tree/3a7954cfb8ee4f1132c83cd1859753294ee8964b).
Definitions explicitly cover the earlier verified Forever builds; the supplied
71037 tables have the same reviewed hashes. Per-section relationships and copied
rows retain their original foreign keys.

| Table | File ID | Layout hash |
| --- | ---: | --- |
| UiMap | 1957206 | DB51D55F |
| UiMapAssignment | 1957219 | C9CC8DFB |
| UiMapArt | 1957202 | 3AE7D144 |
| UiMapXMapArt | 1957217 | EAE7DA2A |
| UiMapArtTile | 1957210 | 2DA5B77B |
| UiMapArtStyleLayer | 1957208 | 3F597F5A |
| WorldMapOverlay | 1134579 | 9A196494 |
| WorldMapOverlayTile | 1957212 | 2C843422 |

The collector also reads continent WDT minimap indexes and existing pinned
city/cave numeric references. It extracts a conservative candidate superset,
bounded to 2,048 textures / 128 MiB raw artwork, with individual textures at
most 16 MiB / 16,777,216 declared pixels. ZIP parts remain below 24 MiB. The
entire game and raw DB2 tables are not transferred.

Current deterministic views cover zoom 12/24/36/48 at Booty Bay's production dock
70 locator (`-14277.7,582.9`, Data.lua build 70450), Undercity's actual map-1458
rectangle center, and an Elwynn/Westfall rectangle-overlap region. These are
reproducible presets, not captured player cameras or native zone boundaries.
**Python does candidate collection; production Lua selects and places layers.**

## Render and inspect updates

In the existing receiving Lua/Pillow environment:

```sh
python3 tools/maplab/run.py --client-bundle /private/TwichUI-map-art-01.zip --client-bundle /private/TwichUI-map-art-02.zip --output test-output/maplab-real --strict
```

Repeat `--client-bundle` for every numbered part. The importer rejects unsafe
paths, incompatible metadata, missing members and integrity failures. Preserve a
baseline, inspect actual PNGs with a vision tool, correlate visual defects with
production Lua and exported state, then rerender the same bundle with
`--baseline test-output/maplab-real`. Report the inspected artifacts and measured
changes. Pixel differences quantify change; they do not establish artistic
quality. No source or generated Blizzard/OpenMap-edited artwork is redistributed.

Native area shapes, phases/conditional artwork, exploration state, exact GPU
sampling and client performance remain outside table-derived reproduction.
Pinned city/WMO geometry still requires native alignment acceptance. This
workflow refreshes **lab inputs/previews**; it does not regenerate production
Data.lua/LocalData.lua, run `tools/mapdata/build.py`, silently install/deploy an
addon, or enable a preprocessed runtime architecture. The full map-data builder
has separate retail/client identity-verification requirements.

## Source kit and focused verification

Build a reusable source-only kit from the current checkout:

```sh
python3 tools/maplab/collect.py --make-kit test-output/TwichUI-maplab-collector.zip
python3 -B tests/test_maplab_extract.py
```

The kit includes `bundle.py`, the maintained README/collector/Windows launcher,
existing CASC/DB2 readers, numeric data and license notices. It includes no
extracted art or screenshots and runs with Python site packages disabled. Use a
current kit after schema/tool/numeric-data updates; old numeric data must not
silently stand in for a changed renderer.

Focused reusable-extractor validation: **16 tests passed**, covering clean and
repeat extraction, changed build/content, missing identity forcing reads,
added/removed IDs, corrupt cached payloads, corrupt or valid-CRC stale ZIPs,
partial/missing/unsupported results, interruptions, path/no-overwrite protections,
metadata binding, format/payload limits and stdlib-only source-kit execution.
Read-only validation of all **1,812 actual legacy payloads** succeeded with zero
missing/unsupported records (106,728,632 raw bytes, approximately 0.83 seconds on
the cloud CPU). This is raw header/hash validation, not gaming-PC extraction
performance. See the real-art results document for the completed image-based
iteration and subsequent integration/regression evidence.
