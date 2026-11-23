# TwichUI Map Lab: collect, update, inspect

Use this maintained collector whenever the Forever client or map code changes.
It needs **Python 3.10+ and its standard library only** on the gaming PC: no Lua,
Pillow, pip packages, administrator access, game launch or login. It never uses
network services, uploads data, reads account/WTF/SavedVariables files, writes to
the game installation, decrypts assets, injects code or reads process memory.

From a checkout or extracted source kit, run one command with your actual path:

```powershell
py -3 tools/maplab/collect.py --wow "D:\Games\World of Warcraft" --output "test-output\maplab-client-input"
```

PowerShell also supports `python` instead of `py -3` when Python is installed
without the launcher. On Linux/WSL, use the corresponding mounted client path:

```sh
python3 tools/maplab/collect.py --wow "/mnt/d/Games/World of Warcraft" --output test-output/maplab-client-input
```

Or double-click **Collect-Map-Art.cmd** and select `_forever_` or the installation
root in the folder picker. The selected folder and its two nearest parents are
checked for `.build.info`/`Data`; product selection uses installed metadata,
including the active build. An ambiguous installation reports valid `--product`
values. Do not guess an unlisted product. The default destination is this kit's
`test-output/maplab-client-input`, outside all addon packages. Explicit paths do
not require a graphical session. Native Windows folder-picker/command-file
operation still needs owner acceptance; fixture tests exercise the Python logic.

## Repeat the same command after updates

A directory destination is a reusable private cache:

- `versions/<build>-<digest>/` holds immutable validated `client.json`, raw
  textures, a schema-2 manifest and ready-to-transfer ZIPs.
- `current.json` points to the latest **successful** version. A partial update
  preserves the previous successful pointer and artifacts.
- `latest.json` also identifies an inspectable partial version, if one exists.
- `latest-update.json` records build changes and added/changed/removed assets,
  fresh reads, reused files and missing inputs.

The collector rereads current map tables/indexes. A prior raw texture is reused
only if the current CASC content key matches, product/root-locale selection is
compatible, and its saved SHA-256/header still validates. A missing content key
forces a fresh archive read. Changed IDs/content are reread, removed IDs are
reported and excluded from the new bundle. Corrupt prior caches are not trusted;
a fresh validated repair gets a separate version. Old outputs are never silently
overwritten. An interrupted/failed attempt leaves the successful pointer intact.
Published versions remain available for comparisons; you may remove older
versions manually after keeping any needed baseline. Do not remove the version
named by `current.json` while collection is running.

The script prints `validation=success`, `partial` or an explicit failure. This
means bounded header/hash/source-accounting validation, **not successful pixel
decoding, native rendering or artistic acceptance**. Missing/encrypted and
unsupported files are listed. Partial results must not be described as complete.
Failed input is not promoted. Header checks inspect BLP/DDS dimensions/format
and declared mip ranges without decoding pixels. The receiving lab performs
actual decoding and rendering. Do not change schema pins to bypass a future
unsupported-client error: update the tool after reviewing that build's schema.

Example summary for a complete 1,812-texture fresh run (illustrative; counts and
builds vary, and this is not a claim of native Windows testing):

```text
Selected installed product: wowf
Forever 1.60.1.71037: 52 map records, 1812 candidate textures
Prepared 1812 textures (101.8 MiB), 0 unavailable; validation=success
Update: build False -> 1.60.1.71037; reused 0, fresh 1812, added 1812, changed 0, removed 0
PRIVATE INPUT: .../versions/<build>-<digest>/TwichUI-map-art-01.zip (... MiB)
```

An unchanged repeat should report reused assets instead of fresh archive reads.
For errors: install Python 3.10+ if the launcher is missing; use an explicit
`--wow` path if the picker fails; select the installation root or `_forever_` for
missing `.build.info`; use only the printed `--product` choices for ambiguity.
An unknown table layout needs an updated tool. Missing/encrypted/unsupported
art remains partial; update/repair the client normally and retry. Integrity
failures require recollection or returning every matching ZIP part, never
editing hashes. If publication fails, use a new local NTFS/ext4 cache directory;
previous verified output remains available.

The manifest records actual client build/product, tool/schema version, input
metadata digest, numeric-data/table hashes, candidate IDs, payload SHA-256,
source CKeys when available, declared texture headers, settings, unavailable
files and validation results. The reader currently selects **enUS-compatible
CASC root blocks**. It does not observe the native client's selected locale;
`clientLocale` is truthfully `unknown`. No selectable localization or localized
art fidelity is promised by a folder name or build string.

## Share only the printed private ZIPs

Each independent ZIP part stays below 24 MiB. Attach **all** printed ZIP paths to
the existing private debugging conversation. There is no automatic upload. A
new explicit `--output issue-map-art.zip` is still supported; existing ZIPs are
never overwritten, and this mode does not retain a reusable cache. ZIP
publication uses exclusive same-filesystem hard links (ordinary NTFS/ext4
support, no elevated access); unsupported filesystems report an error without
replacing previous outputs. Prefer a local cache folder rather than a network
or synchronization drive.

Keep private game-art caches, ZIPs, screenshots and derivatives out of Git and
addon releases. The recommended `test-output/` is already ignored/excluded.
Possession of extracted artwork grants no redistribution rights. The source
kit itself contains only source/numeric data/license notices and can be rebuilt:

```sh
python3 tools/maplab/collect.py --make-kit test-output/TwichUI-maplab-collector.zip
```

The kit includes this README, shared manifest/header validation, the collector,
local CASC/DB2 readers, numeric map data and the Windows launcher. Use the latest
source kit after tool/schema/numeric-data changes; update the existing cache
with it. Do not reuse an old kit's numeric data to claim a newer renderer's view.

## Inspect in Codex/the offline lab

The receiving environment additionally needs the repository's existing Lua/Pillow
setup. Existing schema-1 ZIPs remain importable with explicit legacy provenance
limitations; schema-2 bundles add current validation and metadata binding.

```sh
python3 tools/maplab/run.py --client-bundle /private/part-01.zip --client-bundle /private/part-02.zip --output test-output/maplab-real --strict
```

Open the HTML gallery, inspect the actual PNGs with a vision tool, correlate
findings with production Lua/state, fix a supported defect, and rerun the same
bundle with `--baseline test-output/maplab-real`. The collector extracts a
conservative candidate superset; **production Lua selects and places layers**.
Client tables approximate APIs, not native phase/zone shapes, and native-client
acceptance remains outstanding. See `docs/maplab-real-artwork.md` for schema,
limits and the established real-art inspect/fix/retest results.

This workflow refreshes lab inputs and previews. It **does not rewrite production
Data.lua/LocalData.lua, invoke the full map-data generator, install/release an
addon or switch the runtime renderer to preprocessed assets**. The full
`tools/mapdata/build.py` has separate retail/client-identity verification inputs;
do not substitute this candidate collector for that generation process.
