# Releasing TwichUI

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

## Required owner settings and pending public promotion

This PR implements release isolation and publisher integrity, **not a completed public
promotion workflow**. Keep `.github/release-policy.json` false. No alpha, beta, stable or
hotfix can be published by Actions in this workflow, even if that flag changes accidentally.
The retained publisher CLI is an operator tool, not an approval system; do not use it to
bypass the pending promotion workflow or hold.

Before a separate reviewed promotion implementation:

1. Protect main: require pull requests, owner review and the `verify` check from this
   workflow (select its actual check context after its first run); prohibit force pushes
   and deletion. Apply protections to administrators; keep bypass lists restricted.
2. Protect `v*` release tags against creation, update and deletion except the deliberately
   authorized release identity. Preserve all existing public tags and release history.
3. Create a `release` environment with owner/maintainer required reviewers, prevent
   self-review, disable administrator bypass, and restrict deployment branches to protected
   main (add a specific temporary release branch only when explicitly needed). If the GitHub
   plan cannot enforce reviewers, leave publication disabled. Do not weaken these settings.
4. Move `CF_API_KEY` from repository secrets to that environment. Grant contents-write only
   to the eventual protected publish job; builds and PRs must have no publication credentials.

The next implementation must support a separate manual promotion selecting immutable
artifact ID/run, full source SHA, channel, version and SHA256. Display that tuple **before**
environment approval, download that exact artifact, compare it to the approval inputs,
verify package/notes/provenance and policy from protected main, and upload without rebuilding.
Serialize all promotions globally. The approval must not float to a branch's latest commit.
Plain workflow_dispatch alone is insufficient; protected environment review is the simplest
supported additional approval. No promotion job or end-to-end approval rehearsal is claimed here.

Release decisions still required: owner real-client v1.3 acceptance; alpha tester scope and
visible omissions; beta/stable certification for the exact final bytes; stable version from
existing history; and hotfix scope. Before beta/stable publication run the full release gate
in docs/testing.md and record client acceptance. That certification is pending, not part of
this development campaign. If stamping beta as stable changes bytes, certify/bind the new
final hash; never call those archives byte-identical.

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
