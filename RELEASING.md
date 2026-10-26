# Releasing TwichUI

Releases are built and published by `.github/workflows/release.yml`, with `tools/release.py` deciding the
version and the release notes. No version or changelog needs editing by hand.

| You push | Channel | GitHub | CurseForge |
| --- | --- | --- | --- |
| a commit to `main` | alpha | prerelease (never "Latest") | alpha file |
| a commit to `beta` | beta | prerelease (never "Latest") | beta file |
| a tag `vMAJOR.MINOR.PATCH` (e.g. `v1.0.0`) | release | release, marked Latest | release file |

Nothing else publishes: not other branches, not pull requests, not tags of another form (`v1.1.0-beta1` is
ignored).

## One-time setup
1. The repository root holds six addon folders, `!!!TwichUI/` (the core addon, with `!!!TwichUI.toc`),
   `TwichUI_Settings/` (the settings window), `TwichUI_NavData/` (navigation's walking maps), `TwichUI_Diagnostics/`
   (profiling and support), `TwichUI_Layouts/` (layout packages) and `TwichUI_LayoutWizard/` (the layout setup), beside the repository-level files: `.pkgmeta`, `.github/`, `tests/`,
   `tools/`, `docs/`, `README.md`, `CHANGELOG.md`, `LICENSE` and `licenses/`.
2. The CurseForge project ID is in `!!!TwichUI/!!!TwichUI.toc` as `## X-Curse-Project-ID:`.
3. Repository secret `CF_API_KEY`: a CurseForge API token (CurseForge > My API Tokens) that can upload to the
   project. GitHub releases use the workflow's own `GITHUB_TOKEN`; no other secret is needed.
4. Settings > Actions > General > Workflow permissions: the publish job asks for `contents: write`. If an
   organization policy caps the token at read-only, publishing fails at the GitHub step (before CurseForge).
5. Create the `beta` branch when you want beta builds; until it exists there are none.
6. Recommended (repository settings, not done by the workflow): a tag ruleset so only maintainers can create,
   move or delete `v*` tags; and, if you want a manual approval before anything is published, an environment
   with required reviewers referenced from the publish job (`environment: release`).

## Versions
One version string per build, used for both `.toc` files, the zip name, the GitHub tag and title, and the
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

The version is written into both `.toc` files in the build's working copy only. Nothing is committed and the
repository stays as it is, so the `## Version:` committed in the `.toc` files is what an unpackaged copy (a
local checkout, `tools/deploy.sh`) shows; it is no longer changed for releases. In game, `/tui version`, the
group check and the diagnostics report the packaged version.

TwichUI's group check compares the `MAJOR.MINOR.PATCH` part only: `1.0.1-alpha.23...` counts as 1.0.1.

## Each stable release
1. Optional, before tagging: `./tools/update_training_data.sh` and commit it if it changed (the build refreshes
   the packaged data anyway; committing keeps GitHub's "Source code" archives the same as the zip), and
   `./tests/run.sh`. `docs/release-hardening.md` has the support scope, the profiling steps and the in-game
   checklist. If the release changes what is saved, follow `docs/persistence.md` ("Adding a schema 2") first.
2. Tag the commit and push the tag:
   `git tag v1.0.1 && git push origin v1.0.1`.
   To add hand-written highlights above the generated notes, make it an annotated tag:
   `git tag -a v1.0.1 -F highlights.md` (the message is Markdown; a message that is only the tag name is ignored).
3. The workflow tests, packages and publishes. Check the run's summary for the version and notes.

Pushing `main` and the tag together is fine: the alpha build of a commit that carries a stable tag is skipped
(if the branch push is processed before the tag arrives, an alpha of that commit is published as well; harmless).

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
The publish job works in steps, recording each in the GitHub release it creates:

1. Create a **draft** GitHub release for the tag (not visible to players, no tag yet) and attach the zip and
   `release.json` (read by addon managers that install from GitHub).
2. Upload the zip to CurseForge, once. The draft's last line records the outcome
   (`<!-- twichui-release {... "curseforge": "uploaded" ...} -->`).
3. Publish the GitHub release, which creates its tag on the built commit, and check the tag points there.

Re-run a failed run with **Re-run failed jobs**: the build is not repeated and publishing continues from the
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
clone, so `git push --tags` can't bring them back): a pushed `v3.0.x` tag would publish that old version as Latest.
Saved data is upgraded by its schema number, not by the addon version, so going from 3.0.12 to 1.0.0 changes
nothing for players' saved settings.

## Keeping prereleases
Nothing is deleted automatically: every alpha and beta stays on GitHub (as a prerelease with its tag) and on
CurseForge. If the list grows too long, delete old prereleases by hand (on GitHub, the release and its tag).
Notes stay correct: the next build's notes then start from the nearest prerelease that is left, or from the
last stable tag.

## Notes
- The build refreshes `!!!TwichUI/modules/TrainingData.lua` from the newest What's Training? commit before
  packaging and fails if fetching, generating or validating it fails. It logs the upstream commit and warns when
  the zip's data differs from the commit's.
- CurseForge's game version comes from `## Interface:` (16001 -> WoW: Forever 1.60.1, as the packager names it).
  If CurseForge doesn't list it, the newest lower Forever version is used, with a warning in the run.
- Keep the `!!!` folder name: TwichUI must load before other addons, and the game names saved variables files
  after the folder.
- The zip holds six folders: `!!!TwichUI`, and `TwichUI_Settings`, `TwichUI_NavData`, `TwichUI_Diagnostics`,
  `TwichUI_Layouts` and `TwichUI_LayoutWizard` (each load on demand; `.pkgmeta` `move-folders`: the packager builds the
  whole repository as the package folder, so the core addon is moved up over it and the others out beside it; the
  wizard also requires `TwichUI_Layouts`, which the build checks). The build checks the zip: exactly those six folders,
  nothing nested or misspelled, every `.toc` file at the build's version with the committed Interface, every file the
  `.toc` files load present, and no development files, machine paths or secret-like text.
- The packager (BigWigsMods/packager, pinned in the workflow) only builds; it uploads nothing.
- Wago and WoWInterface are not set up: there is no `X-Wago-ID` or `X-WoWI-ID`, and the workflow doesn't upload
  there.
- The CurseForge description can reuse README.md.
