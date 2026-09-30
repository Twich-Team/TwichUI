# TwichUI — Claude Code instructions

## Project

TwichUI is a World of Warcraft addon targeting **WoW: Forever**.

Treat this project’s files and the target client as the source of truth. Do not assume this is a Retail or Classic addon just because APIs or examples look similar.

## Before making changes

- Read the addon's `.toc` file, existing documentation, and relevant source files before editing.
- Learn the actual directory structure and follow existing naming, initialization, event, and UI patterns.
- Identify the specific behavior the requested change should produce. If an important requirement is unclear, ask before making a broad or irreversible change.
- Prefer the smallest change that fully solves the request. Avoid unrelated cleanup, renaming, reformatting, or redesign.
- Do not invent project conventions, supported game versions, API behavior, or test results.

## WoW: Forever API and compatibility

- Target **WoW: Forever**. Do not use Retail, Classic, or legacy API assumptions without verifying that they apply to the target client.
- The local Blizzard UI source reference is expected at `../wow-ui-source/`. Its `forever` branch is the preferred source for client-specific API documentation and implementation examples.
- Before using an unfamiliar, changed, restricted, or security-sensitive API:
  1. Search the local Forever UI source and API documentation.
  2. Check existing uses in this addon and relevant Blizzard UI code.
  3. If the reference does not establish the behavior, say what is unknown rather than guessing.
- Treat API stubs, editor completion, third-party guides, and examples from other game versions as aids—not proof that an API works in Forever.
- Be particularly careful with protected/secure UI behavior, combat lockdown, secret values, and APIs whose behavior may vary by client version. Do not attempt to bypass Blizzard's restrictions.
- Preserve the target game interface/version metadata in the `.toc` unless the task explicitly requires changing it. Verify the correct value from the target client/reference; do not guess it.
- Do not copy Blizzard UI source into this addon unless explicitly requested and its license/attribution requirements have been checked.

## Lua and addon conventions

- Follow the code style and patterns already present in the addon.
- Preserve the addon's existing namespace, initialization flow, saved-variable names, event handling, and load order.
- Keep the `.toc` file's load order correct when adding, removing, or renaming files.
- Use descriptive names and local variables where appropriate. Avoid introducing globals unless the WoW API or an established addon pattern requires them.
- Check event and callback arguments against the target-client documentation; do not rely on remembered signatures.
- Keep changes compatible with the Lua version supported by the target client. Verify syntax/features against project configuration or target-client evidence; do not assume a modern desktop Lua version.
- Avoid unnecessary dependencies. Do not add a library or embed code from another addon without asking and checking the project's existing dependency and licensing conventions.
- Do not add debug output, slash commands, settings, or user-facing behavior unless the task calls for it or the project already has an established pattern.

## Working with files

- Treat the repository as the source of truth. Do not edit the deployed copy in the WoW AddOns directory.
- Do not overwrite or delete user changes unrelated to the task.
- Do not include `Zone.Identifier` files, editor state, generated artifacts, local credentials, or machine-specific paths in commits.
- Keep generated or downloaded API references outside the addon source unless they are intentionally part of the project.
- Never put secrets, access tokens, or personal information in source files or Git.

## Testing and validation

- First inspect the repository for its actual test, lint, build, packaging, or deployment commands. Do not invent commands or claim they passed without running them.
- After changes, run relevant available checks, such as Lua syntax/static checks or the project's own scripts. Report any tool that is unavailable.
- Review the final diff for unintended changes, incorrect `.toc` load order, accidental generated files, and changes to game-version metadata.
- Static checks cannot prove in-game behavior. Clearly distinguish checks you ran from tests that still need to be performed in WoW: Forever.
- Do not claim an API or UI behavior is verified in-game unless it was actually tested in the target client.
- Do not deploy, publish, upload, release, or commit changes unless the user explicitly asks.

## Response format

When finishing a task, report:

- What changed and why.
- Which files changed.
- Checks actually run and their results.
- Any in-game testing still required or assumptions that remain.