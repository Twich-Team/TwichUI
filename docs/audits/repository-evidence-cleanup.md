# Repository evidence cleanup

2026-11-16. Baseline `feb1a583ac1a46f9bcadfdd69a604fb3c65560bf`.
[Audit PR #36](https://github.com/Twich-Team/TwichUI/pull/36) passed its final
`verify` check (23 s), contained only the expected report and was merged normally
at that commit. Publication remains disabled. Cleanup is isolated on
`engineering/repository-evidence-cleanup`; it is not authorized for merge here.

## Actual checkout changes

All sizes are logical Git blob payload, not compressed transfer or filesystem
allocation. No history rewrite, clone-size or runtime-package saving is claimed.

| Scope | Before files / bytes | After files / bytes | Removed |
|---|---:|---:|---:|
| Historical `test-output/` | 606 / 54,133,698 | 340 / 36,957,973 | 266 / 17,175,725 bytes |
| Duplicate documentation images | 3 / 4,498,988 | 0 / 0 | 3 / 4,498,988 bytes |
| Total removed paths | 269 / 21,674,713 | — | 21.67 decimal MB |

Whole repository: 2,482 → 2,218 tracked files; 292,572,990 → 271,041,638 bytes.
After added policy, hash inventory, collector and tests, the net checkout payload
reduction is 21,531,352 bytes (21.53 decimal MB). The 340 retained historical
files hold all 340 distinct original blobs. No unique historical bytes were discarded.

The [retention inventory](../evidence/historical-output-retention.csv) gives
original and retained paths, sizes and SHA-256 for all 606 original output files
plus three removed documentation copies. Each removal was compared byte for
byte before deletion; every retained file was subsequently hash-checked.
All 40 distinct linked historical output files remain at their original paths,
so their documentation needs no relocation. Copies are consolidated only when
not referenced in Markdown links or literal repository paths. Historical JSON,
failure records, copied baseline sources and all unique images remain unchanged.

Approved design references stay under `docs/reminders-revision/`. The three
unreferenced exact copies in `docs/reminders-style-references/` are removed;
existing component tools and documentation already use the retained paths.
No source art, runtime art or fixture was removed. No expiring archive is used
as the sole retained copy of any historical evidence.

## Future evidence

[Retention policy](../evidence/README.md) uses the existing pinned Actions upload
mechanism. Verification diagnostics are collected/uploaded with `always()` after
success or failure, bounded to 20 MiB / 500 payload files, with 14-day expiration.
Reports precede logs/telemetry, which precede PNGs; omitted files are explicit.
The manifest includes retained hashes, source/fixture/scenario identities and
platform/Python/Lua versions. No caches, staged addons, temporary fixtures or
historical screenshot directories are uploaded. No simulator is added to CI.
New tracked `test-output/` paths are refused, including forced adds and moves;
ignore rules continue to cover local generation. Permanent results require a
reviewed compact summary and selected evidence in Git before artifacts expire.

## Verification and deferred work

- **Unit-tested:** seven collector/workflow controls, including failed report
  retention, budget limits, hashes, symlink handling, missing Lua, existing-output
  refusal and the real workflow Git guard for additions/moves/removals.
- **Unit-tested:** `development release-tools` passed all three modules; artwork
  checks passed five Wizard and eleven Reminders gallery cases, including rebuilt
  byte parity and corruption controls. No test expectation/seed was narrowed.
- **Source/structural checks:** all 609 retention rows and 269 mappings checked;
  no removed-path inputs in tests/tools/workflows; no new missing Markdown targets;
  generated-output ignores, workflow YAML, publication hold and diff whitespace
  checked. All runtime/source-art/fixture trees and `.pkgmeta` are unchanged.
- Collector exercised against real focused-run output: five diagnostic files /
  3,853 bytes, zero omissions. This is local collection evidence; hosted artifact
  upload will be exercised by normal PR CI.
- **Not tested:** full simulator certification, real-client behavior or a rebuilt
  release ZIP. Runtime package equivalence is established by unchanged package
  source trees and packaging policy, rather than an unnecessary packaging run.

There are 113 pre-existing missing Markdown targets, largely historical local
simulator/output references; none are introduced by this cleanup. Existing links
to retained evidence and all new policy links resolve. Repairing unavailable
historical references without their original evidence is deferred, not silently
replaced with new captures. Unique legacy evidence (36.96 MB), copied baseline
source, runtime/source art and all required fixtures remain until a separately
verified retention/reproducibility decision exists. Market functionality, release
authorization and regression coverage remain unchanged.

Rollback: revert this normal commit to restore the former duplicate paths and
previous artifact handling. No Git tags, releases or old commits are changed.
