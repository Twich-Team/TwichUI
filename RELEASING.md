# Releasing TwichUI

## One-time setup
1. Put this folder in a GitHub repository (the repository root is this folder).
2. Create the project on CurseForge (World of Warcraft > Addons). CurseForge
   projects are public once approved. Note the **Project ID** on the project page.
3. Add it to `!!!TwichUI.toc`: `## X-Curse-Project-ID: 123456`.
   (Optional: `## X-Wago-ID: xxxxxx` for Wago Addons.)
4. Create a CurseForge API token (CurseForge > My API Tokens) and add it to the
   GitHub repository as the secret `CF_API_KEY` (and `WAGO_API_TOKEN` for Wago).

## Each release
1. Update `## Version:` in the TOC and add an entry to `CHANGELOG.md`.
2. Run `./tools/update_training_data.sh` (needs `git` and `lua5.1`) to refresh the
   class training data from the newest What's Training? commit, then
   `./tests/run.sh` (needs `lua5.1` and `lua-bitop`).
   If the release changes what is saved (a new or changed layout in any saved variable), follow
   `docs/persistence.md` ("Adding a schema 2") first: a numbered, repeatable upgrade step and a test with the
   previous layout.
3. Commit (including `modules/TrainingData.lua` if it changed), then tag and push:
   `git tag v3.0.1 && git push --tags`.
4. The GitHub Action refreshes the training data again, tests, packages (folder `!!!TwichUI`, without tests/ and
   .github/) and uploads the release. Friends using the CurseForge app or WowUp
   get it as a normal update.

## Notes
- The release job refreshes `modules/TrainingData.lua` before packaging and fails the
  release if fetching, generating or validating it fails. The uploaded zip contains the
  refreshed data. A tag is never rewritten, so GitHub's automatic "Source code" archives
  hold whatever was committed at the tag: step 2 keeps them the same as the zip. The job
  logs the upstream commit and warns when the zip's data differs from the tagged commit.
- Mark the release for the right game version on CurseForge. Forever reports
  interface 16001; if CurseForge doesn't list it, upload for the closest version
  CurseForge offers and say "WoW Forever" in the release notes.
- Keep the `!!!` folder name: TwichUI must load before other addons.
- The CurseForge description can reuse README.md.
