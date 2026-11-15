# Reminders gallery PNG reproducibility

## Audit and contract

Base: feature/workshop 916a0a97458d1acfb533ac736ea7bc269e9c6a9d.
PR #15 is unmerged. Its migration proposal was read from compatibility commit
a9dd1dae790170b061e7056c53740ac7b55a4a2f; this PNG branch does not include it.
The PNG PR targets feature/workshop independently. Cloud tests use a temporary
integration worktree with #15; that integration is not pushed as the PNG branch.

The failing assertion is tests/test_reminder_gallery.py, Rebuild's exact PNG byte
comparison. Matching pixels alone is insufficient. The writer emits filter-0,
192x192 RGBA8 PNGs: IHDR, one IDAT, IEND, no profiles/timestamps/metadata. It used
zlib.compress(raw, 9), whose compressed bytes depend on undocumented producer
behavior. Python/zlib 1.2.13, 1.3.1 and 1.3.2 probes did not recover the reference
stream. The original encoder/build is not established. Differences are in IDAT
and derived length/CRC, not image content. The decoder uses standard PNG filters,
but the shared artwork read_png additionally clears alpha <=8: it is NOT used as
the sole preservation check. Exact decompressed scanlines cover hidden RGB/alpha.

Inputs are the unchanged RGBA8 sheets icon-grid-1.png (1536x1024) and
icon-grid-2.png (1024x1536) in docs/reminders-revision. Explicit SHEETS and entry
lists, sorted component positions and fixed resampling parameters determine the
67 output images. No directory traversal order or filesystem timestamps feed
image encoding. Source crop/resampling/color/alpha logic remains unchanged.
Runtime outputs are 134 uncompressed RGBA TGAs (128px/64px); addon references,
ArtData.lua, manifest, source sheets, QA/contact sheets and unrelated art stay
unchanged. The migration inventory lists every old/new PNG SHA256, size, raw
scanline hash and runtime TGA hash. No runtime appearance changes are permitted.

## Canonical encoding: gallery-rgba-stored-v1

Instead of pinning a compressor build, remove the compressor decision entirely.
Use the existing stdlib-only Python 3 pipeline with explicitly serialized RFC
1950/1951 stored blocks. There is no compression-library encoding dependency.
Standard CRC32/Adler32 algorithms remain checksums, not heuristic compressors.

- PNG: RGBA8, non-interlaced, filter zero per row, network-order dimensions.
- Exactly IHDR, one IDAT and IEND; CRC32 on each chunk; no metadata or color profiles.
- Zlib header 78 01; no dictionary. Stored DEFLATE blocks of exactly 65535 bytes
  except the last, length/complement little endian, zero padding bits, BFINAL
  only on last block. An empty input has one empty final block. Adler32 big endian.
- Repository version and golden-vector tests pin these bytes. No Pillow,
  ImageMagick, OS paths, environment settings or zlib.compress defaults are used.
- Only the 67 generated gallery source PNGs are migrated. They grow because they
  now store scanlines verbatim. assets/ is excluded from packaging; runtime TGAs
  and all game-visible data are unchanged.

The earlier proposal's alternative was a pinned Debian compressor/toolchain and
an approved baseline update. This implementation keeps its full content/TGA review
requirements, but removes the compressor pin by fully specifying the byte format.
Python still performs the unchanged resampling; independent Python 3.12/3.13
full-build comparisons test that part without claiming WSL execution.

## Migration evidence and acceptance commands

The reviewed inventory is [reminder-png-migration.json](reminder-png-migration.json):
67 PNG old/new hashes and sizes, exact preserved scanline hashes, all 134 unchanged
runtime TGA hashes, and manifest/ArtData/input-sheet hashes. All original and
regenerated IHDR and decompressed scanlines matched, including low-alpha hidden
RGB. Both full canonical builds (Python3.12.14 and3.13.5) matched byte for byte.
No old PNG bytes were inferred from the shared alpha-normalizing decoder.
Source PNG total: 3,772,224 -> 9,897,642 bytes. No contact/QA sheet or unrelated
PNG is rewritten. No zlib encoder, image package or runtime artifact is added.

Regular tests retain the original sample byte comparisons and now rebuild all
67 images/134 TGAs. They also verify inventory hashes, canonical block layout,
RFC vectors, boundaries/empty streams, CRCs, hidden RGB and invalid dimensions.
Changing either a generated PNG or TGA must fail the existing byte assertion.

Native WSL acceptance (pending; not claimed from Cloud):

```sh
python3 -B -m unittest discover -s tests -p 'test_reminder*.py'
python3 -I -B tools/make_reminder_gallery.py --out-root /tmp/twichui-png-a
python3 -I -B tools/make_reminder_gallery.py --out-root /tmp/twichui-png-b
# Both output roots must be new/disposable. Review all file hashes against the
# committed inventory and each other; ensure no production checkout was rewritten.
diff -qr /tmp/twichui-png-a /tmp/twichui-png-b
bash tests/run.sh fast reminders
bash tests/run.sh
```

After PR #15 is included in a separate local integration checkout (or merged by
reviewers), also run the unchanged local `bash tests/run.sh full` with authorized
game assets. In Cloud, the integration command is
`bash tests/run.sh full --profile cloud`. Neither changes this PR's target branch
nor replaces local real-client/font/visual acceptance. Do not merge either PR
as part of this campaign.

Fresh-task acceptance remains manual: this session has no independent task-create
or snapshot-restore tool. In a genuinely new task verify the intended PNG commit,
clean task branch, Lua5.1/luac5.1/bitop/Python3 and activated dependency paths;
read-only research source bebcb6bf309cf41b41bd74f8ca651e6a105b2676
(1.60.1.70938), pinned source ca8368f2f2380cbe696854f7f2646387c278a61b
(1.60.1.70532), checksum-verified v0.1.37 archive and ICU/ALSA dependencies.
Check WOWSIM_INSTALL/WOWSIM_LAB and SIMLAB_UI_SOURCE, writable ignored artifacts,
32GiB-or-appropriate memory feasibility and serial simulator/layout safeguards.
Then run gallery byte tests, fast reminders, and smoke/feature via the explicit
#15 integration. Record actual counts and exits; never infer restoration from a
same-machine worktree or report no-assets screenshots as real-client fidelity.
