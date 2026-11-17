# Test evidence retention

Generated reports, logs and captures belong in ignored `test-output/`, not new
tracked files there. CI rejects additions even if force-added. Keep compact
conclusions and selected permanent evidence under `docs/evidence/` in a reviewed
commit; do not copy whole run directories, caches or baseline source trees.

## Historical evidence kept in Git

[Retention inventory](historical-output-retention.csv) records the original path,
current retained path, byte length and SHA-256 for all 606 historical output files
and three consolidated documentation images at baseline
`feb1a583ac1a46f9bcadfdd69a604fb3c65560bf`.
For a removed path, use `retained_path` to open its exact bytes in the current
checkout. All 40 distinct historical output files linked from Markdown remain at
their existing paths. Unique images, failure records, metadata and baseline source
copies remain in Git; there is no external archive or expiration promise.

The three approved design images remain in `docs/reminders-revision/`, where
existing documentation and component tools already read them. Their identical,
unreferenced copies under `docs/reminders-style-references/` were removed.
The inventory preserves both their former names and their hashes. Historical
metadata is unchanged; old machine-local simulator paths in it are provenance,
not a promise that the original simulator workspace is still available.

## Future CI diagnostics

The existing verify job collects diagnostics with
`tools/collect_verification_evidence.py` even after verification fails, then uses
the existing pinned Actions upload action. It does not change test selection,
assertions or failure status. Each run/attempt gets a distinct artifact name.

- Retain at most 20 MiB / 500 files, prioritizing runner reports, then logs and
  telemetry, then screenshots. Omitted files and their sizes are listed; retained
  files are never truncated and include SHA-256 hashes.
- Collect only verification reports/logs and simulator artifact directories.
  Exclude temporary test fixtures, historical review folders, staged addons,
  caches, home and WTF. Ordinary CI runs no simulator, so it uploads no catalog.
- Include commit/tree IDs, fixture/scenario tree IDs, CI run identity, platform,
  Python and Lua versions. Runner reports retain source fingerprints, selections,
  outcomes and the actual simulator artifact paths. No full environment dump.
- Artifacts expire after **14 days**. Download useful failures before expiry.
  Before a result becomes a permanent documentation dependency, commit a compact
  summary plus selected exact evidence, hashes and source/runtime/fixture identity
  under `docs/evidence/`. Expiring artifacts are never permanent archives.
- Evidence beyond the budget remains in the original local output; review the
  omission list. Retain a specific diagnostic subset separately when necessary,
  rather than raising the global budget or automatically uploading every image.

Cleanup is a normal commit: revert it to restore former paths. No history rewrite,
source-art deletion, runtime-media relocation or new storage service is involved.
[Measured cleanup](../audits/repository-evidence-cleanup.md).
