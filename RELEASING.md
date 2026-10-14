# Releasing TwichUI

## One-time setup
1. Put this folder in a GitHub repository (the repository root is this folder). The root holds two addon folders,
   `!!!TwichUI/` (the core addon, with `!!!TwichUI.toc`) and `TwichUI_Settings/` (the settings window), beside the
   repository-level files: `.pkgmeta`, `.github/`, `tests/`, `tools/`, `docs/`, `README.md`, `CHANGELOG.md`,
   `LICENSE` and `licenses/`.
2. Create the project on CurseForge (World of Warcraft > Addons). CurseForge
   projects are public once approved. Note the **Project ID** on the project page.
3. Add it to `!!!TwichUI/!!!TwichUI.toc`: `## X-Curse-Project-ID: 123456`.
   (Optional: `## X-Wago-ID: xxxxxx` for Wago Addons.)
4. Create a CurseForge API token (CurseForge > My API Tokens) and add it to the
   GitHub repository as the secret `CF_API_KEY` (and `WAGO_API_TOKEN` for Wago).

## Each release
1. Update `## Version:` in both TOCs (`!!!TwichUI/!!!TwichUI.toc` and `TwichUI_Settings/TwichUI_Settings.toc`;
   `tests/test_settings_package.lua` fails if they differ) and add an entry to `CHANGELOG.md`.
2. Run `./tools/update_training_data.sh` (needs `git` and `lua5.1`) to refresh the
   class training data from the newest What's Training? commit, then
   `./tests/run.sh` (needs `lua5.1` and `lua-bitop`).
   `docs/release-hardening.md` has the support scope, the profiling steps and the in-game checklist to go through first.
   If the release changes what is saved (a new or changed layout in any saved variable), follow
   `docs/persistence.md` ("Adding a schema 2") first: a numbered, repeatable upgrade step and a test with the
   previous layout.
3. Commit (including `!!!TwichUI/modules/TrainingData.lua` if it changed), then tag and push:
   `git tag v3.0.1 && git push --tags`.
4. The GitHub Action refreshes the training data again, tests, packages (folder `!!!TwichUI`, without tests/ and
   .github/) and uploads the release. Friends using the CurseForge app or WowUp
   get it as a normal update.

## Notes
- The release job refreshes `!!!TwichUI/modules/TrainingData.lua` before packaging and fails the
  release if fetching, generating or validating it fails. The uploaded zip contains the
  refreshed data. A tag is never rewritten, so GitHub's automatic "Source code" archives
  hold whatever was committed at the tag: step 2 keeps them the same as the zip. The job
  logs the upstream commit and warns when the zip's data differs from the tagged commit.
- Mark the release for the right game version on CurseForge. Forever reports
  interface 16001; if CurseForge doesn't list it, upload for the closest version
  CurseForge offers and say "WoW Forever" in the release notes.
- Keep the `!!!` folder name: TwichUI must load before other addons.
- The zip holds two folders: `!!!TwichUI` and `TwichUI_Settings` (the settings window, load on demand; `.pkgmeta`
  `move-folders`: the packager builds the whole repository as the package folder, so the core addon is moved up
  over it and the settings window out beside it). Unzip a release once to check both are there, side by side, that
  `!!!TwichUI` has its `.toc` at its top (not a second `!!!TwichUI` folder inside it) and no `TwichUI_Settings`
  folder, and that there is no other top-level folder in the zip.
- The CurseForge description can reuse README.md.
