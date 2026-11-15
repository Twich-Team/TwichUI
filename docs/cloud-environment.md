# Cloud verification compatibility

Use the existing task checkout; do not create a worktree unless requested.
The cloud compatibility task branch is `codex/cloud-compatibility`, based on
`feature/workshop` at `916a0a97458d1acfb533ac736ea7bc269e9c6a9d`.
Do not push changes directly to the shared development branch.

## Explicit profile, unchanged local gate

Initialize the prepared machine with `source /workspace/twichui-env/activate.sh`.
Run from the repository root:

```sh
bash tests/run.sh fast workshop-settings
bash tests/run.sh feature workshop-settings --profile cloud
bash tests/run.sh full --profile cloud --list
# Full cloud run, once smaller checks pass and failures are resolved:
bash tests/run.sh full --profile cloud
```

`--profile cloud` changes only simulator asset mode to `SIMLAB_ASSETS=0`.
It preserves the exact same test discovery, assertions, syntax coverage,
simulator catalogs, independent replay and deliberately wrong controls selected
by the tier. No environment pose, seed, or fixture-generation filters survive.
A verified `SIMLAB_BIN` runtime launcher may supply workspace shared libraries;
it does not change simulator source or the pinned v0.1.37 binary.
Reports record the profile and unsupported rendering coverage. A cloud result
never sets `local_milestone_passed`; even a full cloud pass is not a full local
milestone pass. Default `--profile local` behavior and CI discovery are unchanged.

All scenarios can be invoked with the documented no-assets switch: these load
Blizzard's pinned UI Lua and real addon Lua from the installed lab. Initialization,
synthetic state/handler assertions, replay and negative controls remain meaningful.
Screenshot commands still render actual frames and bundled addon textures using
software Vulkan and fallback resources; missing external textures and game fonts
are NOT validated. Existing image assertions remain active and may fail; a
no-assets failure is reported, never skipped or relabeled as supported.
No-assets mode cannot establish game-asset rendering, client fonts, wrapping or
visual fidelity. Combat/taint, secure actions, actual input, message delivery and
reload persistence still require a real client. No proprietary assets are fetched.

For individual representative catalogs:

```sh
SIMLAB_ASSETS=0 bash tools/simlab/run.sh smoke
SIMLAB_ASSETS=0 bash tools/simlab/run.sh diagnose
SIMLAB_ASSETS=0 bash tools/simlab/run.sh auctionproof
SIMLAB_ASSETS=0 bash tools/simlab/run.sh auctionpreview
```

Execute simulator commands via the supported elevated command path if the outer
sandbox prevents nested Bubblewrap namespaces. The inner lab restrictions remain
intact. Installed references and dependencies are read-only; mutable state is
isolated under ignored `test-output/simlab/`, with a serial simulator lock.
Do not edit files during a simulator catalog (its repository-status guard is active).

## Smoke error classification

The default simulator adds a sample party after login. The 3-second party hello
can run during smoke's fade advancement depending on startup timing. Its arbitrary
LibSerialize/LibDeflate payload triggers the established simulator string rule:
`string at argument 2 is not valid UTF-8`. Previous smoke used a blanket zero-error
check instead of the existing delayed-error classifier. This was a verdict mismatch,
not evidence of an addon regression or an asset/shim version change.

Smoke now discloses that existing rule only with ChatThrottleLib `PerformSend`
and the `Share.lua`/`SendControl`, `Group.lua`/`SayHello` stack chain. The original
log is retained; tick markers record when it occurs. Other errors, the same text
from another origin, and missing classifier context fail. The page-construction
sweep remains strict. `test_simlab_smoke.py` verifies these failure paths; the
existing diagnostics contract also probes invalid UTF-8 without any addon loaded.
This classification says nothing about the real client's transport contract.

Smoke also covers six seconds of manual-clock advancement, crossing the native
five-second audio-settings ticker instead of depending on startup phase. Its
existing `voice-settings-unsupplied` rule is permitted only when a read-only
`pcall` probe confirms that the actual C binding raises the exact missing-capability
message. The full error must occur between this fixture's clock markers, with
only the observed native `AdvanceTime`/fixture-main traceback and optional
Blizzard error-report frames. An addon frame, absent probe, different message,
out-of-window error or uncorroborated suppressed summary fails. No native API is
replaced. The construction sweep remains strict. Reproduction, negative controls
and complete regression evidence are in
[AH integration verification](workshop/auction-house/integration-verification.md).


## PNG reproducibility remains a gate

`tests/test_reminder_gallery.py`, `Rebuild.test_sample_pictures_are_what_the_tool_builds`
requires exact PNG bytes. The four sample IDs are reminder-lion-shield,
reminder-expiring-buff, reminder-fishing-rod and reminder-low-mana. Generated files
are built in temporary folders, never over committed production images.

Decoder: `tools/make_map_tool_icons.py:read_png`. Encoder:
`tools/make_reminder_gallery.py:png_rgba`, stdlib `zlib.compress(raw, 9)`.
Both lion-shield PNGs contain only IHDR(13), IDAT, IEND(0), with no timestamps or
other ancillary metadata. IDAT is 56,073 bytes stored versus 56,365 regenerated.
Decompressed scanlines are identical (147,648 bytes, SHA256
`297e1beeec5609f8abc52b5fc51cde8a3eda2125d149b6e54e5ac891252ab3ec`).
All four decoded samples and all eight runtime TGAs match. Only compression and
its derived chunk length/CRC differ. That does not satisfy the byte-level contract.

Python 3.12.14/zlib 1.3.2, Python 3.13.5/zlib 1.3.1, and authenticated Debian
shared zlib 1.2.13 all reproduce the mismatch. The documentation names Python 3
but does not pin the original compressor/build; PNG headers do not identify it.
No verified matching encoder has been recovered. The original failing assertion
is unchanged and remains visible. Neither matching pixels nor the older library
probe is reported as a pass.

If the original encoder cannot be recovered, a separately approved migration is:

1. Select an authenticated, checksum/version-pinned encoder and record its source,
   build options, Python and zlib runtime in a reproducibility manifest.
2. Regenerate the complete artwork into a disposable root; compare decoded RGBA,
   alpha, dimensions, manifest, ArtData and every runtime TGA to the old baseline.
3. Require human review of any semantic difference and explicit approval for the
   PNG baseline update; do not update references just to accommodate this host.
4. Rebuild twice from clean roots with the pinned encoder, require byte equality
   between builds and committed references, then run the entire existing gallery
   suite and local milestone gate. Keep the byte-exact assertion.

Tradeoff: a reviewed compression-only baseline change can remove portability
ambiguity, but still changes source artifact bytes and requires intentional
review. Pixel comparison alone would be a different, weaker contract and is not
part of this change.

## Restoration acceptance

Install/start instructions are saved through the environment draft. This session
cannot invoke a new cloud task or snapshot restore. After publication/reprovision,
verify references/commits, binary hashes, tool activation, fast/feature profiles,
smoke, failure controls and PNG status in a fresh task. Same-instance install
replay is not restoration evidence. No automatic publication is requested.

## Evidence from this compatibility task

- Unit-tested: fast workshop-settings, 11 passed; cloud feature workshop-settings,
  84 passed plus three Workshop launches and 1,580 structured checks, PASS.
- Simulator-tested: final smoke PASS (56/56 pages); diagnostics PASS (six launches,
  including the no-addon message contract and classifier rejection controls);
  auctionproof PASS (four launches, replay and wrong control); auctionpreview PASS
  (complete default catalog, replay and wrong control). All used no-assets mode.
- Screenshot-reviewed: final smoke settings.png generated at 1600x1200 and opened;
  structural only. The original captured UTF-8 hello log passes the narrow rule;
  that real log with an appended unexpected Lua error fails the final verdict.
- Full offline run: 231 passed, two failed, 474.442 seconds. One was the known
  gallery byte mismatch; the other was an isolated sibling import introduced by
  the first smoke patch. That import is fixed and the affected decoder/smoke/runner/
  workflow modules were rerun successfully. This is a targeted correction after
  the full run, not a second green comprehensive run. The gallery failure remains.
- The unchanged full local milestone and full cloud simulator catalogs were not
  executed: the known gallery gate is still red. Selection parity for both profiles
  was checked (233 offline modules/files and all ten full simulator catalogs).
- No OOM event occurred. Setup replay passed on this task branch. Fresh-task
  restoration and all real-client acceptance remain untested.

Initial investigation left changes staged on `codex/cloud-compatibility`; no push or
publication was performed. Preservation and commit handoff follow in
[the readiness checklist](cloud-readiness-handoff.md). The GitHub API returned Forbidden, so no PR was created; the cloud
working diff and an external patch artifact are available for review.
