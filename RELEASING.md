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
2. Run `./tests/run.sh` (needs `lua5.1` and `lua-bitop`).
3. Commit, then tag and push: `git tag v3.0.1 && git push --tags`.
4. The GitHub Action tests, packages (folder `!!!TwichUI`, without tests/ and
   .github/) and uploads the release. Friends using the CurseForge app or WowUp
   get it as a normal update.

## Notes
- Mark the release for the right game version on CurseForge. Forever reports
  interface 16001; if CurseForge doesn't list it, upload for the closest version
  CurseForge offers and say "WoW Forever" in the release notes.
- Keep the `!!!` folder name: TwichUI must load before other addons.
- The CurseForge description can reuse README.md.
