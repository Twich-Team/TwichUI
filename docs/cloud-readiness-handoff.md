# Compatibility preservation and restoration handoff

Scope: test infrastructure and documentation only, on `codex/cloud-compatibility`,
based on `916a0a97458d1acfb533ac736ea7bc269e9c6a9d`. No production addon or
reference source changes; no PNG migration. See [migration proposal](png-migration-proposal.md).

## Installation and startup

The full install script and startup instructions are saved in the environment
draft, with retrievable copies in `/workspace/twichui-env/handoff/`. They install
verified workspace dependencies, retain the two read-only Forever references and
verify the pinned simulator archive/libraries/UI manifest. Do not infer readiness
from saved instructions alone. Base Git, Python, bubblewrap, curl, dpkg-deb, flock
and standard shared libraries must exist; installation fails if prerequisites or
Git ancestry do not match. Never reset local work or silently select another branch.
There is no environment-settings branch selector: verify the existing checkout
and create an isolated task branch containing the intended baseline when needed.

In every shell:

```sh
source /workspace/twichui-env/activate.sh
cd /workspace/TwichUI
bash tests/run.sh fast workshop-settings
bash tests/run.sh feature workshop-settings --profile cloud
```

No persistent server is required. Run simulator commands with supported elevated
execution if nested Bubblewrap namespaces are blocked; retain its inner sandbox.
For individual smoke: `SIMLAB_ASSETS=0 bash tools/simlab/run.sh smoke`.
Artifacts remain in ignored test-output directories, never in addon assets or
reference checkouts. Install replay is not fresh-task restoration evidence.

## What is established, and what is not

- Passing earlier same-instance checks: fast 11 files; cloud feature 84 files,
  Workshop design/craft/wrong (3 launches, 1580 checks); smoke 56/56 pages;
  diagnostics six launches; AH lifecycle and complete preview catalogs including
  independent replay/negative controls. Screenshots were opened as structural
  evidence only. A real captured hello error plus an unexpected injected error
  correctly failed the smoke verdict.
- Corrected import: the final focused decoder/smoke/runner/workflow modules passed
  23 Python cases. Preservation-time final runs are recorded with the artifacts.
- Comprehensive offline result remains **231 passed, 2 failed** before the import
  correction. The import failure was fixed and targeted tests rerun; the entire
  suite has NOT been rerun since that correction. Do not claim 232/1 as an actual
  complete-run result. The existing gallery PNG byte-exact assertion still fails.
- Full cloud simulator and full local milestone catalogs were NOT run. Exact
  profile selection parity was checked, not comprehensive execution equivalence.
- Cloud supports no-assets Lua/synthetic handler/state, replay and failure-control
  verification with existing assertions. Default local workflow remains unchanged.
- Local-only: authorized game-asset rendering/fonts, actual client appearance,
  input, combat/taint/secure actions, message delivery and reload persistence.
- No new cloud task/restore can be invoked with current tools. No environment
  publication, release or shared-branch push is authorized by this handoff.

## Fresh-task restoration acceptance checklist (pending)

1. Retrieve/verify the saved commit or bundle and patch checksums before ending
   this task. Restore the snapshot through the supported product flow manually;
   do not equate a same-machine clone with a new environment.
2. Verify Git remote, branch, exact HEAD and clean worktree. Preserve unrelated
   work; confirm the compatibility commit is present and the development baseline
   is its ancestor. Do not push directly to feature/workshop.
3. Activate the shell and verify Linux Git, Lua5.1, luac5.1, require('bit'), Python3,
   rsync, bubblewrap and Mesa runtime. Run the saved install script only if setup
   needs reproduction; retain TLS, package-signature and checksum verification.
4. Verify read-only research reference forever commit
   bebcb6bf309cf41b41bd74f8ca651e6a105b2676/build1.60.1.70938 and pinned simulator
   source ca8368f2f2380cbe696854f7f2646387c278a61b/build1.60.1.70532.
5. Verify v0.1.37 simulator archive SHA256
   66e9afa95b61619fb15af335c74a8e9e2b0cc645d9bbf078dca492ec8bf8dfae,
   ICU/ALSA hashes and source manifest. Check WOWSIM_INSTALL/WOWSIM_LAB,
   SIMLAB_UI_SOURCE, verified runtime launcher and writable ignored artifact roots.
6. Check memory limits/OOM counters; keep layout tests serial and simulator
   catalogs locked/serial. Run fast, final focused Python tests, cloud feature,
   smoke, diagnostics and representative AH scenarios. Verify report timestamps,
   profile, counts, underlying exits and deliberate rejection controls. Open the
   newly generated screenshot; never claim visual fidelity from fallback rendering.
7. Run the unchanged gallery check and report its actual failure until a separately
   approved migration passes. After resolution, rerun complete offline and full
   cloud verification, then the unchanged full local WSL gate with game assets.
8. Record exact results as passed/failed/unsupported/not run. Only then reassess
   fully verified status. Current recommendation is coding-ready with known limits,
   NOT fully verified or an all-green publication baseline.

GitHub API access previously returned Forbidden. Do not try alternate credentials.
A local commit, self-contained Git bundle, email-format patch, setup copies and
checksums are provided for retrieval; publication/PR creation is not claimed.
