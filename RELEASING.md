# Releasing TwichUI

Development uses protected main and short-lived reviewed branches; see [Git workflow](docs/git-workflow.md). Candidates are frozen from exact verified commits, without a permanent release branch.

Verification and internal builds run in `.github/workflows/release.yml`. Public publication
is disabled. `tools/release.py` retains version/history and publisher integrity tooling.

**v1.3 publication hold:** `.github/release-policy.json` currently disables publication.
Branch merges can proceed without creating a tag, GitHub release or CurseForge upload.
The workflow planner reports `publish=false`, and the publish CLI also refuses the hold.
Owner real-client acceptance and explicit authorization are required before a separate
reviewed change enables publication. Local candidate packaging and archive checks remain available.

For a local v1.3 candidate without publication, use a separate **clone** at the
frozen commit (the pinned packager expects a `.git` directory). Keep the owner
checkout untouched. Write local metadata with a candidate `version`, its exact
`commit` and `publish: false`; stamp only that disposable clone with
`python3 -I tools/release.py stamp --meta /absolute/path/meta.json`. Download
`release.sh` from the same packager commit pinned in the workflow,
`e50a250f8705041e40f2fa1ddcb280a686d65aa0`, inspect it and run:

```sh
bash /absolute/path/release.sh -d -t /absolute/path/build-clone \
  -r /absolute/path/candidate-output -n '!!!TwichUI-v<CANDIDATE-VERSION>-forever'
python3 -I tools/release.py check --meta /absolute/path/meta.json /absolute/path/candidate.zip
```

`-d` means build only. Do not run the publish command or create a tag. Include all
seven production addon folders according to `.pkgmeta`; exclude development
companions. A `1.3.1-rc.1.g<sha>` candidate follows the existing `v1.3.0` baseline
without inventing a new public version tag. Keep the packaged version out of
committed `.toc` files. The consolidation archive uses committed training data;
it does not silently fetch a different runtime dataset during certification.

## Development and internal builds

PRs targeting main and pushes to main run `Verify and build internally / verify`.
They cannot publish: there is no publishing job, tag trigger, write token or secret.
Manual Actions dispatch on main additionally builds an **uncertified internal** ZIP.
Use the dispatch's selected main commit; the manifest records the full SHA.
Publication policy does not gate verification or internal packaging.

The small CI selector uses the existing `development release-tools` tier for changes
confined to release tooling/documentation. All other or unknown scopes use the existing
complete offline runner, without simulator catalogs. This is deliberately conservative;
use the documented feature/integration tiers for additional affected-feature evidence.

Internal artifacts include meta.json, notes.md and the checked seven-addon ZIP, retained
30 days. Names include source SHA, run ID and attempt. No overwrite is allowed. A rerun
creates a new internal candidate, never permission to replace an accepted public candidate.
Internal versions (`0.0.0-dev.g<SHA>`) are not public version plans or certified releases.

## Explicit candidates and promotion

There are three workflows: normal verification/internal builds (`release.yml`),
manual candidate creation (`release-candidate.yml`), and protected manual promotion
(`release-promotion.yml`). All manual workflows run from **main** only. Source inputs
must be full commit SHAs, never floating branch names. Nothing publishes on pushes/tags.

1. Choose a reviewed source commit and final version. Run **Build release candidate**
   on main with source, channel (`alpha`, `beta`, `stable`, `hotfix`) and version.
   Prereleases use `N.N.N-alpha.COUNT.gSHA7` / `N.N.N-beta.COUNT.gSHA7`; stable/hotfix
   use `N.N.N`. Use reachable history as described below; do not renumber old releases.
   Hotfix additionally requires a reachable stable `hotfix_base` tag and its next patch.
   Normal candidates must be ancestors of main; hotfixes may be on their released line.
   The requestor must have write/maintain/admin permission. The build has no publication
   secrets, uses trusted main tooling with separate source checkout, stamps all seven TOCs,
   packages committed inputs, checks the ZIP, seals it and uploads without overwrite.
2. Record the **artifact ID**, source SHA, version, channel and **ZIP** SHA256 from the
   summary/meta.json. GitHub's artifact-container digest is different from the ZIP digest.
   Download that ID for testing. Certify the final stamped bytes; never build during promotion.
3. Commit exact-candidate evidence through a reviewed PR on main at
   `docs/releases/<ZIP-SHA256>.json`, using the format below. Alpha requires feature/package
   verification, client/tester acceptance evidence and explicit scope/limitations. Beta,
   stable and hotfix also require a passing full release profile for this ZIP and explicit
   real-client acceptance. Link retained reports; the ledger is a reviewed maintainer
   attestation, not an automatic claim that the linked client tests were performed.
4. For stable/hotfix, after certification create an **annotated** `vN.N.N` tag on the exact
   source using the authorized maintainer identity. Tagging alone uploads nothing.
   Existing tags are never moved/replaced. The publisher verifies the annotated tag and
   an active no-bypass `refs/tags/v*` update/deletion ruleset before publication.
5. Run **Promote exact release candidate** on main with the five recorded identifiers.
   Preflight verifies maintainer permission, protected main, protected environment,
   successful main-dispatched candidate origin, artifact ID/age/expiry, package/hash/notes,
   version history, reviewed evidence and stable tag protection. It displays the exact tuple
   before environment approval. **While publication_enabled is false, publication is skipped.**
6. After a separately reviewed future authorization lifts the hold, the authorized maintainer
   explicitly approves their own release through the `release` environment job (GitHub
   **Review deployments → Approve and deploy**). Its name includes version, channel, artifact ID
   and full digest; its environment URL links to the exact source/tuple summary. The job
   re-downloads the **same ID**, repeats validation and checks the latest main hold before
   credentials/upload. It never rebuilds or re-stamps. Global concurrency serializes all
   channels, including approval waits. GitHub may replace a pending queued request; it
   never cancels a running publisher. A displaced request must be deliberately dispatched again.

```json
{
  "candidate": {
    "artifact_id": "123456789",
    "source": "FULL_40_HEX_SOURCE_SHA",
    "version": "1.3.1",
    "channel": "stable",
    "sha256": "FULL_64_HEX_ZIP_SHA256"
  },
  "verification": "https://github.com/Twich-Team/TwichUI/...exact-candidate-report...",
  "client_acceptance": "https://github.com/Twich-Team/TwichUI/...owner-acceptance...",
  "release_gate_passed": true,
  "client_accepted": true,
  "limitations": "Actual alpha scope/omissions, or certified release limitations"
}
```

Do not set acceptance flags for a cloud-only/focused run. The full release/client checks
are pending before the first real beta/stable/hotfix publication; this campaign does not
run them. A beta-to-stable version stamp changes bytes: create/certify a new stable
candidate and ledger/digest. Internal `0.0.0-dev` artifacts cannot be promoted.

Actions artifacts expire after 30 days; missing, older, deleted or expired candidates are
rejected. Preserve final ZIP/meta/notes and certification evidence securely for support.
If a candidate expires before acceptance, create a new candidate and review/certify its
new digest/ID. Never rewrite an accepted release marker to pretend a rebuild matches it.
If expiry occurs after a partial public release, reconcile existing destinations and
retained original bytes manually; automatic promotion does not rebuild or guess identity.

## Solo-maintainer GitHub settings

One maintainer can request and approve a release. Manual dispatch selects the exact
candidate; it is **not** approval. After preflight, open the waiting `release` deployment,
compare its source/version/artifact ID/SHA256 with the certified candidate, then select
**Review deployments → Approve and deploy**. No second person is required. The environment
must still have a required reviewer: removing reviewers would remove the manual gate and
is rejected. A requester still needs repository write/maintain/admin permission.

Keep these settings:

1. **Rules → main**: require PRs and the `verify` check, prohibit force pushes/deletion,
   no bypass actors. For solo development, zero required PR approvals and no last-push
   approval requirement lets the owner merge their own passing PR. Release approval is
   a separate environment action.
2. **Rules → release tags**: active `v*` update/deletion protection, no exclusions or
   bypass actors. Stable/hotfix promotion requires an annotated matching tag. Do not
   move existing tags. This implementation creates/changes no release tags.
3. **Environments → release**: add the owner (currently `rldiamond`) as a required reviewer;
   **Prevent self-review OFF**, **administrator bypass OFF**, deployments limited to
   **protected branches only**. Review remains mandatory even when the requester approves.
4. **Environment secrets → release → CF_API_KEY**: configure the upload token here and
   remove any repository-level copy. Builds and ordinary PR jobs never receive it.

Configuration inspection on 2026-11-16 confirmed protected main with PRs/`verify` and no
force pushes/deletion or bypass actors; the active no-bypass `v*` tag ruleset; and the
required owner reviewer, self-review allowed and protected-branch restriction in `release`.
The environment API also explicitly returned `can_admins_bypass=false`, confirming that
setting for this inspection. Environment-secret listing returned HTTP 403, so the token's
presence/scope was **not verified**. Confirm it in Settings; never send secret values in chat.
No GitHub settings were changed by this implementation.

The validator accepts an explicit API `can_admins_bypass=false` and rejects enabled or
invalid values, even if policy claims otherwise. If GitHub omits that field, automation
cannot verify the UI toggle: it requires the existing reviewed owner attestation
(`environment_admin_bypass_disabled=true` and an HTTPS `environment_configuration_evidence`
link in `.github/release-policy.json`). Do not invent those values. This PR leaves both
unchanged/empty and keeps `publication_enabled=false`. If the API omits the field later,
the owner must supply real evidence through a reviewed PR before promotion can proceed.

The publication hold still skips the publishing job. Before the first real release,
record exact-candidate certification/client acceptance and separately authorize lifting
the hold. Solo approval changes neither the package hash/version checks nor the safe
recovery rules below. No public release is performed by this change.

## Branch policy

Use protected main and short-lived feature/bug-fix branches. Use a temporary release branch
only when concurrent stabilization needs one. Hotfixes may start at the affected public tag;
port the fix back to main once. Promote releases explicitly. Do not reverse-merge long-lived
branches just to equalize SHAs after documentation changes. This change deletes/renames no branches.

## Versions
One version string per build, used for all seven `.toc` files, the zip name, the GitHub tag and title, and the
CurseForge display name:

- Stable: the tag without its `v`. Tag `v1.0.0` -> `1.0.0`, `!!!TwichUI-v1.0.0-forever.zip`. A stable tag must be
  newer than every stable tag its commit already contains, or nothing is published.
- Alpha and beta: `<next patch>-<channel>.<commits>.g<commit>`, for example `1.0.1-alpha.23.g3e8a397`:
  - `<next patch>`: the patch after the highest stable tag the commit contains (after `v1.0.0`: `1.0.1`).
    A prerelease never guesses whether the next release is a patch, minor or major; the stable tag decides
    that, and `1.0.1-alpha...` sorts below any of them.
  - `<commits>`: how many commits the build is past that tag, so builds on one branch count up.
  - `g<commit>`: the first 7 characters of the commit it was built from.
  - A tag the commit does not contain (made on another branch) does not count: the version says what the
    build contains. So a `beta` branch that has not merged `v1.0.1` still builds `1.0.1-beta...`.
  - Before the first stable tag, prereleases build toward the first release, 1.0.0:
    `1.0.0-alpha.<all commits>.g<commit>`.
- The same commit always gets the same version, so a re-run makes the same release, not a second one.
- At most 40 characters: shared setups keep the addon version only up to that length.

The version is written into all seven `.toc` files in the build's working copy only. Nothing is committed and the
repository stays as it is, so the `## Version:` committed in the `.toc` files is what an unpackaged copy (a
local checkout, `tools/deploy.sh`) shows; it is no longer changed for releases. In game, `/tui version`, the
group check and the diagnostics report the packaged version.

TwichUI's group check compares the `MAJOR.MINOR.PATCH` part only: `1.0.1-alpha.23...` counts as 1.0.1.

## Reviewed build inputs

Training updates are a development action: fetch a chosen upstream commit with the existing
update tool, review the generated TrainingData.lua and provenance header, and commit them
before candidate creation. Packaging uses that committed file; it does not fetch upstream or
change runtime training data. The packager itself remains pinned by commit. There are no
external `.pkgmeta` source inputs. Keep source/tag/version and final ZIP hash with certification.

A stable tag identifies the chosen version; pushing it does not authorize or trigger publication.
The legacy planner retains history-compatible versions/notes for future promotion integration.

## Release notes
Generated from commit messages, the same Markdown for GitHub and CurseForge:

- Range: alpha, since the nearest earlier published alpha this commit contains; beta, likewise for betas;
  stable, since the highest earlier stable tag the commit contains. With no earlier one on the channel, since
  the last stable tag; with none at all, the whole history (at most 100 entries are listed).
  "Published" means a tag made by this workflow, and ancestry decides "earlier", not the tag's name. A build
  that failed never made a tag, so the next one covers its commits too.
- Merge commits are left out; the commits they bring in are listed. A squash merge is one commit, listed once.
  Commits with the same message are listed once.
- Conventional Commits are understood but not required: `feat:` goes under Features, `fix:` under Fixes,
  `perf:` under Performance, a `!` or `BREAKING CHANGE:` is marked Breaking, and `build`, `chore`, `ci`,
  `docs`, `refactor`, `style` and `test` commits are counted but not listed. Every other message is listed
  under Changes as written.
- Left out: `fixup!`/`squash!`/`amend!` commits and messages containing `[skip changelog]` or `[no changelog]`.
- Commit text is shown as plain text (Markdown, HTML and @mentions are neutralized).
- The notes are only as good as the commit subjects: write them for players ("Vendor restocking: ask before buying"), not "refinement".

The first release (no earlier stable tag) lists no commits, only "The first release." and its highlights: write
them in the annotated tag.

`CHANGELOG.md` keeps the notes written by hand during development (the 3.0.x builds) and is no longer updated.

## Re-runs, failures and recovery
The retained publisher (currently unreachable from Actions and blocked by the hold) works in steps:

1. Create a **draft** GitHub release for the tag (not visible to players, no tag yet) and attach the zip and
   `release.json` (read by addon managers that install from GitHub).
2. Upload the zip to CurseForge, once. The draft's last line records the outcome
   (`<!-- twichui-release {... "curseforge": "uploaded" ...} -->`).
3. Publish the GitHub release, which creates its tag on the built commit, and check the tag points there.

Candidate metadata must first be sealed with `release.py seal --meta ... --zip ... --notes ...`.
Sealing validates all packages and records ZIP SHA256, filename, full commit, version, channel
and notes SHA256. Re-sealing existing metadata verifies it instead of overwriting identity.
The publisher compares this identity to the draft marker, then downloads and hashes GitHub
assets before any CurseForge upload. Both destinations receive the same checked local ZIP.
A changed local ZIP, notes or identity, or corrupt remote asset, fails closed. Historical
records without candidate metadata require operator reconciliation against retained bytes,
source and destination evidence; never invent a hash from a newly rebuilt ZIP. The tool
provides no automatic migration of historical drafts. Preserve uncertain-upload state.

After future promotion is reviewed, **Re-run failed jobs** using the original artifact: the build is not repeated and publishing continues from the
recorded step. What each failure leaves:

- Tests or packaging failed: nothing was published. Fix and push again.
- CurseForge refused the file (an error answer, or it could not be reached): the draft says `"failed"`.
  Fix the cause (for example the `CF_API_KEY` secret), then re-run: it uploads again.
- CurseForge's answer was lost (timeout, server error) or the job stopped mid-upload: the draft says
  `"unknown"` or `"uploading"`, and re-runs stop rather than risk a second file. Look at the project's Files
  on CurseForge for the file named in the error. If it is there, edit the draft and change the state to
  `"uploaded"`; if not, change it to `"retry"`. Then re-run.
- The GitHub release could not be published after CurseForge took the file: re-run; CurseForge is not uploaded
  again.
- A tag of that name already exists on another commit, or a release of that name exists that this workflow
  did not make: nothing is published. Sort out the tag or release by hand.
- A file published to CurseForge by mistake: CurseForge's project page lets you archive or delete it; the
  workflow never deletes anything. For GitHub, delete the release and its tag.

## Versions before 1.0.0
TwichUI was built as 3.0.x during development; the first release for WoW: Forever's launch is 1.0.0. The 3.0.x
tags are kept as `archive/v3.0.1` ... `archive/v3.0.12`: outside `v*`, so they publish nothing and don't count
as stable tags. Never push a `v3.*` tag again (keep the `archive/` names, and delete stray `v3.*` tags in any
clone, so `git push --tags` cannot bring them back). Tags alone no longer publish.
Saved data is upgraded by its schema number, not by the addon version, so going from 3.0.12 to 1.0.0 changes
nothing for players' saved settings.

## Keeping prereleases
Nothing is deleted automatically: every alpha and beta stays on GitHub (as a prerelease with its tag) and on
CurseForge. If the list grows too long, delete old prereleases by hand (on GitHub, the release and its tag).
Notes stay correct: the next build's notes then start from the nearest prerelease that is left, or from the
last stable tag.

## Notes
- CurseForge requires an **exact** Forever type/name mapping (Interface 16001 -> 1.60.1,
  gameVersionTypeID 88568). Missing mappings fail before upload. No compatibility fallback
  is implemented. Any future override needs explicit owner compatibility approval recorded
  against the candidate and a separately reviewed implementation; a warning is insufficient.
- Keep the `!!!` folder name: TwichUI must load before other addons, and the game names saved variables files
  after the folder.
- The zip holds seven folders: `!!!TwichUI`, and `TwichUI_Settings`, `TwichUI_NavData`, `TwichUI_Diagnostics`,
  `TwichUI_Layouts`, `TwichUI_LayoutWizard` and `TwichUI_Workshop` (each load on demand; `.pkgmeta` `move-folders`: the packager builds the
  whole repository as the package folder, so the core addon is moved up over it and the others out beside it; the
  wizard also requires `TwichUI_Layouts`, which the build checks). The build checks the zip: exactly those seven folders,
  nothing nested or misspelled, every `.toc` file at the build's version with the committed Interface, every file the
  `.toc` files load present, and no development files, machine paths or secret-like text.
- The packager (BigWigsMods/packager, pinned in the workflow) only builds; it uploads nothing.
- Wago and WoWInterface are not set up: there is no `X-Wago-ID` or `X-WoWI-ID`, and the workflow doesn't upload
  there.
- The CurseForge description can reuse README.md.
