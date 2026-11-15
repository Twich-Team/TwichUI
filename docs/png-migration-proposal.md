# Proposed deterministic PNG baseline migration — NOT APPROVED OR EXECUTED

The current byte-exact assertion remains active and failing. This proposal changes
no production artwork, runtime textures, encoder code or test expectations.
The original encoder has not been identified; this is a new reviewed baseline,
not a claim to reproduce the old compressed stream.

## Candidate toolchain and encoding contract

Use Debian 13 amd64 with CPython **3.13.5**, authenticated Debian packages:

- `python3.13-minimal=3.13.5-2+deb13u5`
- `libpython3.13-minimal=3.13.5-2+deb13u5`
- `zlib1g=1:1.3.dfsg+really1.3.1-1+b1` (zlib **1.3.1**)

These are installed, supported distribution packages, not unverified binaries.
The installed candidate reports GCC 14.2.0 and zlib build/runtime 1.3.1.
Record all transitive runtime package versions in the eventual build manifest.
Archive authenticated `.deb` files and their SHA256 values before approving the
migration; use a signed Debian snapshot/package index, never a moving unverified
container tag. If these versions cannot be retrieved with signature verification,
stop rather than silently substituting another version. No container digest is
invented here; any eventual container must be pinned to its actual reviewed digest.

Observed candidate binary SHA256 values (to verify the proposed runtime, not old
PNG provenance):

- `/usr/bin/python3.13`:
  `889c603f0d17cb54060951bcf4c4f9b8c9ebd9e52b392c70209bbb9755d797d9`
- `/usr/lib/x86_64-linux-gnu/libz.so.1`:
  `85590dd58edf5445e18bc7193e5ebc01ac5841f1ae187e97705a662e90c6421e`

Use the existing generator/resampler from the reviewed addon commit; record its
exact Git revision in the manifest. Invoke `/usr/bin/python3 -I -B` with no user
site or injection paths, `LC_ALL=C`, `TZ=UTC`, `PYTHONHASHSEED=0` (isolated mode
already ignores Python environment settings). Future tooling must check the actual
Python and zlib versions before encoding and fail on a mismatch.

Preserve the encoder's existing contract: 192x192 RGBA, 8 bits/channel, row-major
RGBA bytes, a zero filter byte before every scanline, non-interlaced PNG, no
metadata, exactly IHDR/one IDAT/IEND with standard CRC32. DEFLATE: level **9**,
method **8**, windowBits **15**, memLevel **8**, strategy **Z_DEFAULT_STRATEGY**,
normal zlib wrapper, no dictionary and no intermediate flushes; finish with
Z_FINISH. This specifies zlib.compress(raw, 9)'s current defaults explicitly.
Preserve runtime TGA encoding, dimensions, alpha and orientation unchanged.

## Approval and binary review process

1. Freeze the old commit and make a SHA256 inventory of all PNGs, decoded RGBA
   buffers, manifests, ArtData.lua and every large/small runtime TGA. Store the
   toolchain manifest and script revision alongside the inventory.
2. Build the **entire gallery** twice into separate disposable roots with the
   pinned candidate. Never regenerate in the production checkout during review.
3. Require identical PNG bytes between the two builds. Compare every decoded
   pixel/alpha/dimension with the old baseline and require every runtime TGA to
   match byte-for-byte. Manifest and ArtData must also remain byte-identical.
   Any difference here stops the migration and requires separate investigation.
4. Produce a binary-review table for **every changed file**: path, old/new SHA256,
   size, ordered chunk types/lengths, decompressed scanline hash, decoded RGBA
   hash and associated runtime TGA hashes. Require changes confined to IDAT
   encoding and its dependent lengths/CRCs. No metadata changes are permitted.
   Include contact sheets for human review; they supplement exact comparisons.
5. Obtain explicit approval of that inventory and the compression-only baseline
   update. Only then copy approved PNG outputs to tracked baseline paths in an
   isolated migration branch. Review `git diff --numstat` for binary files and
   reject unrelated assets, generated logs, TGA changes or runtime code changes.

## Required regression tests in the migration implementation

Keep the existing exact-PNG-byte assertion. Add tests that:

- rebuild twice in clean roots and compare every PNG, not only four samples;
- rebuild with the pinned toolchain and compare all committed PNG bytes;
- verify full old/new decoded RGBA and runtime TGA inventories;
- validate chunk order, absence of ancillary metadata, scanline filters and
  pinned compressor parameters using a fixed small RGBA fixture and PNG hash;
- reject a mismatching Python/zlib version before writing any output;
- reject a deliberately changed PNG byte/pixel and a changed runtime TGA.

Tests and baseline changes must be reviewed together. Matching pixels alone is
not a replacement for byte equality. No assertion is disabled or marked expected
to fail. A candidate toolchain is not accepted merely because it is available:
its reproducibility and complete pixel/TGA parity must pass before approval.

## Mandatory local WSL acceptance

Run the same pinned amd64 runtime under native WSL Linux, verify package/binary
hashes, and independently rebuild twice from the migration commit in clean roots.
Require identical SHA256 inventories between Cloud and WSL, and unchanged decoded
pixels/runtime TGAs relative to the pre-migration baseline. Run the entire gallery
suite, `bash tests/run.sh`, and the unchanged `bash tests/run.sh full` with the
local authorized game installation. Review the binary inventory/contact sheets
locally. Record exact commits, versions, counts and exit codes; any failed gate
blocks migration acceptance. Real-client rendering acceptance remains separate.
