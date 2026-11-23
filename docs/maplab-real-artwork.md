# One-time real-artwork input for Map Lab

The cloud workspace has no mounted game installation or private artwork cache.
The environment was searched again: `/workspace` (including attachments/shared
downloads), `/mnt`, `/media`, `/opt` and accessible home/temp locations have no
Forever `.build.info`, CASC game archives, map BLPs or client executable. The
simulator's `.idx` files are Mesa shader caches, not CASC archives.

The smallest remaining owner action is to run the read-only collector on the
gaming PC and return its ZIP output. No in-game capture, gameplay, login, full
installation copy, SavedVariables or account files are required.

## Gaming PC: one collection

The prepared source-only kit is
`test-output/TwichUI-maplab-collector-v2.zip` (about 76 KB). It contains only TwichUI
source, existing numeric map data and license notices, with no game artwork.
It can be regenerated from this PR:

```sh
python3 tools/maplab/collect.py --make-kit test-output/TwichUI-maplab-collector-v2.zip
```

1. Download and extract the v2 kit into a fresh folder on the gaming PC. Python **3.10+** is the only
   prerequisite; no Pillow, Lua, pip package or paid tool is needed there.
2. Double-click **Collect-Map-Art.cmd**. Choose **`_forever_`** or the installation
   root containing `.build.info` and `Data`. The collector checks the selected
   folder and its two nearest parents for the archive root.
3. Attach **TwichUI-map-art.zip**, or **all numbered TwichUI-map-art-XX.zip parts**,
   from the extracted kit folder to the existing private Codex conversation.
   Each ZIP part is below 24 MiB. Do not upload the full installation or WTF.

Equivalent command from a checkout of this branch (substitute the actual root):

```powershell
py -3 tools/maplab/collect.py --wow "D:\Games\World of Warcraft" --output TwichUI-map-art.zip
```

Omit `--wow` to use the folder picker. If Python is absent, install it from the
official python.org installer; the collector does not download dependencies.
The collector selects an installed product from **`.build.info`**, using Forever
product/version metadata and active-build information. The folder name is only a
hint; it never invents a product ID. If several products remain ambiguous, the
error lists valid names for an explicit `--product` override. This fixes the old
kit's `product 'wow_classic_beta' not in .build.info` error. Keep any later error
message if the reader refuses a schema or input.
Windows folder-picker/command-file operation has not been exercised on a native
Windows host here; explicit-path collection is covered with isolated fixtures.

The script opens installed archives read-only through `tools/navbake/casc.py`.
It never writes to the client, reads WTF/accounts, uses a CDN, decrypts files,
starts the game, injects code, reads process memory or uploads anything. Missing
local/encrypted textures remain listed in the output rather than substituted.
Existing output ZIPs are not overwritten. Keep extracted game artwork private;
no redistribution rights are inferred.

## What is collected

Eight existing Forever map tables provide parent relationships, actual artwork
file IDs, dimensions and coordinate transforms. Each table's layout and table
hash must match reviewed WoWDBDefs definitions pinned at
[`3a7954cf`](https://github.com/wowdev/WoWDBDefs/tree/3a7954cfb8ee4f1132c83cd1859753294ee8964b).
Those definitions explicitly cover Forever 1.60.1.70450/70532/70938. Unknown
layouts fail before column interpretation. Per-section relationships and copied
rows retain their original foreign keys.

| Table | File ID | Layout hash |
|---|---:|---|
| UiMap | 1957206 | DB51D55F |
| UiMapAssignment | 1957219 | C9CC8DFB |
| UiMapArt | 1957202 | 3AE7D144 |
| UiMapXMapArt | 1957217 | EAE7DA2A |
| UiMapArtTile | 1957210 | 2DA5B77B |
| UiMapArtStyleLayer | 1957208 | 3F597F5A |
| WorldMapOverlay | 1134579 | 9A196494 |
| WorldMapOverlayTile | 1957212 | 2C843422 |

The collector also reads the two continent WDT minimap indexes. It transfers
normalized technical metadata, source hashes, and a conservative texture
candidate set around three locations, bounded to 2,048 textures / 128 MiB raw
artwork. World/continent base paintings, nearby zone paintings and unconditional
overlays, terrain tiles, and existing nearby cave/city references are included.
The entire game and raw DB2 tables are not copied.

The twelve initial views cover zoom 12/24/36/48 at:

- Booty Bay: production dock 70, world yards `(-14277.7,582.9)` on continent 0,
  from existing `Data.lua` build 1.60.1.70450.
- Undercity: the actual map-1458 rectangle's center.
- Elwynn/Westfall: the midpoint of their map-rectangle overlap/boundary region.
  This is a reproducible view preset, not a claim to know the native zone shape.

Each retained BLP/DDS payload has its source/output SHA-256, file-data ID and
client build in the private manifest. The source numeric data hashes must match
the receiving checkout, preventing an apparently faithful view built with a
different set of interior records.

## Codex: consume the returned input

Use the existing cloud Lua/Python environment, then run:

```sh
source /workspace/twichui-env/activate.sh
python3 tools/maplab/run.py --client-bundle /path/to/TwichUI-map-art.zip \
  --output test-output/maplab-real --strict
```

For multiple parts, repeat `--client-bundle` for each ZIP. All parts are required;
build mismatch, missing members, hash mismatch, unsafe paths and oversized input
are refused. Input is unpacked to a temporary directory. Decoded sources are
released between scenes, preserving the existing 32-million-pixel retention
limit within a scene. No release packaging or runtime texture budget changes.

The collector does **candidate extraction**, not map rendering. Validated numeric
metadata passes through a data-only TSV bridge into the existing native-style
fixture. Actual `World.lua`, `View.lua`, `Art.lua`, `Detail.lua`, `Pictures.lua` and
`Caves.lua` then select/place/fade the layers; existing `export.lua` and the
compositor produce the gallery. Collected input is never evaluated as Lua.

This uses **client-table-derived API geometry**, not native API capture. It
preserves UiMin/UiMax partial-art assignments; conflicting affine assignments
are rejected instead of choosing an arbitrary area/floor. Native zone shapes,
conditional/phase artwork, exploration state and native GPU sampling remain
unavailable. Existing pinned WMO/city placement data is still subject to native
alignment acceptance. These limitations accompany generated state/provenance.

## Required inspection loop after input arrives

1. Require real decoded map artwork, a labeled table-derived adapter, recorded
   file/build hashes and explicit missing-asset results. `--strict` must not be
   described as passing if required textures are absent.
2. Inspect Booty Bay, Undercity and border PNGs directly with a vision tool.
   Examine resolution, seams, alpha, coast and interior layering against source
   state. Compare OpenMap only where suitable lawful reference pixels exist.
3. Preserve the initial gallery, fix a source-supported defect, rerender using
   the same input bundle and `--baseline test-output/maplab-real`, then inspect
   differences and affected production tests.
4. Separate an offline correction from native-client reproduction/acceptance.
   Do not infer artistic quality from checksums, placeholders or unit fixtures.

**Current status:** the source kit, bounded transport and production-Lua input
bridge are implemented and contract-tested. The kit runs with Python site
packages disabled. Eight collector/bridge tests and the existing eighteen
compositor tests pass. No actual client archives were available to exercise
end-to-end extraction, and **no real-artwork screenshot/inspection/fix loop has
occurred yet**. That objective remains pending the returned private input.
No new runtime visual correction or production preprocessing switch is claimed.

Verified commands for this input milestone:

- `python3 -B tests/test_maplab_client.py`: **8 passed**, including schema/
  assignment rejection, section/copy relations, read-only collection, multipart
  integrity, path/data rejection, source-kit stdlib-only execution and production
  Lua export using explicitly synthetic unit input.
- `python3 -B tests/test_maplab.py`: **18 passed**.
- `./tests/run.sh feature navigation --profile cloud --jobs 2`: **98 passed,
  zero failures**, syntax and simulator smoke; 86.309 seconds.
- The existing map diagnostics / 4,000-operation course passes; no new warmed
  terrain textures, peak 24 active. Edited fixture/export Lua also passes syntax.

The previous full-suite **324 passed / 1 known Welcome Back failure** evidence is
preserved; this offline-input milestone does not rerun that unrelated full gate.
The original 75,401-byte beta-default kit is superseded by v2. The corrected
76,195-byte kit has SHA-256
`cc5b08e34187178a222fc81ff0ce83c4d919dc667d0d84fa3e9b069464b99b7e`.
Product/subfolder regression checks expand collector coverage to **10 passing
tests**. `./tests/run.sh fast navigation --profile cloud --jobs 2` passes
**43 checks**, zero failures, 25.866 seconds. Product metadata lookup now also
prefers the active build when older rows for the same installed product remain.
