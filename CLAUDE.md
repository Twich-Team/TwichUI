# TwichUI — Claude Code instructions

## Project

TwichUI is a World of Warcraft addon targeting **WoW: Forever**.

It is a focused, carefully curated interface companion—not a full UI replacement or a collection of unrelated utilities. Its purpose is to make the game’s interface clearer, more cohesive, and more enjoyable while keeping the world and the player’s own choices at the center.

Treat this project’s files and the target client as the source of truth. Do not assume this is a Retail or Classic addon just because APIs or examples look similar.

## Product philosophy

TwichUI should feel:

- **Native to WoW: Forever:** It should complement the game’s world, art direction, and interface rather than impose a generic modern UI aesthetic.
- **Refined and understated:** Favor polish, legibility, and useful details over visual noise, large overlays, excessive animation, or novelty.
- **Player-directed:** Inform and assist without prescribing a route, rotation, build, or way to play.
- **Coherent:** New features should feel like parts of one considered addon, not separate utilities bundled together.
- **Optional in depth:** Make common actions easy to find; place technical or rarely changed settings behind simple progressive disclosure.
- **Lightweight:** Prefer small, reliable enhancements over duplicating large addon suites or native game features.

The guiding question for new features is:

> Does this make the game clearer, more personal, or more enjoyable without taking attention away from the world or control away from the player?

Avoid excessive hand-holding, optimization pressure, intrusive prompts, persistent reminders, unsolicited chat, and features that turn play into a checklist.

## Visual direction

Use a warm, restrained visual language that feels at home in WoW: Forever.

- Favor warm charcoal, deep umber, aged bronze, muted gold, parchment, and carefully chosen richer accents over flat near-black surfaces.
- Use pixel-textured borders and subtle material cues where they fit. Ellesmere UI may be an inspiration for texture and finish, but TwichUI must retain its own identity.
- Make important information readable first; texture and decoration must not reduce contrast.
- Avoid generic web-app panels, glassmorphism, neon accents, heavy gradients, excessive glow, and overly ornate fantasy decoration.
- Prefer subtle hierarchy and meaningful color over coloring every element.
- Use animation sparingly. A short, smooth transition should feel like a natural part of the interface, not like an alert demanding attention.
- Respect reduced-motion preferences when adding animation.
- Do not copy Ellesmere UI or Blizzard assets or code unless their source, license, and project conventions have been checked.

A good design metaphor for the Journey Chronicle is a practical, well-used field ledger—not a modern dashboard or a theatrical parchment prop.

## Product scope and current state

TwichUI has included or has been developing features such as gear comparison, addon-configuration sharing and backups, addon-message/chat conveniences, optional addon skins, and the Journey Chronicle.

This is not an authoritative inventory of the current code. Inspect the repository before relying on this list. Do not implement a discussed or planned feature as though it already exists.

Prefer enhancing or integrating with a well-maintained addon when that is more reliable and coherent than rebuilding a large feature. Do not duplicate major systems such as auction management, damage meters, quest routing, or full UI suites without an explicit request.

## Before making changes

- Read the addon's `.toc` file, existing documentation, and relevant source files before editing.
- Learn the actual directory structure and follow existing naming, initialization, event, and UI patterns.
- Identify the specific behavior the requested change should produce. If an important requirement is unclear, ask before making a broad or irreversible change.
- Prefer the smallest change that fully solves the request. Avoid unrelated cleanup, renaming, reformatting, or redesign.
- Do not invent project conventions, supported game versions, API behavior, or test results.
- For feature work with significant architectural uncertainty, inspect first and provide a concise implementation plan before making broad changes.

## WoW: Forever API and compatibility

- Target **WoW: Forever**. Do not use Retail, Classic, or legacy API assumptions without verifying that they apply to the target client.
- The local Blizzard UI source reference is expected at `../wow-ui-source/`. Its `forever` branch is the preferred source for client-specific API documentation and implementation examples.
- Before using an unfamiliar, changed, restricted, or security-sensitive API:
  1. Search the local Forever UI source and API documentation.
  2. Check existing uses in this addon and relevant Blizzard UI code.
  3. If the reference does not establish the behavior, say what is unknown rather than guessing.
- Treat API stubs, editor completion, third-party guides, and examples from other game versions as aids—not proof that an API works in Forever.
- Be particularly careful with protected/secure UI behavior, combat lockdown, secret values, and APIs whose behavior may vary by client version. Do not attempt to bypass Blizzard's restrictions.
- Verify event timing and payloads, asynchronous API responses, load order, and callback behavior from target-client evidence.
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

## Settings and UI architecture

- Persistent TwichUI preferences belong in the native WoW AddOns settings experience.
- Keep complex workflows in focused TwichUI-owned windows when they involve multiple steps, lists, previews, confirmations, or restore operations. Configuration sharing and backup management are workflows, not ordinary settings.
- Do not create two competing places to configure the same TwichUI feature.
- Use Blizzard's native settings controls and visual conventions for TwichUI's category inside Blizzard Options.
- Do not apply Ellesmere UI skinning to Blizzard's shared Options panel. Let Blizzard, or an installed UI addon acting on Blizzard's window, handle that appearance.
- Consider Ellesmere UI styling only for TwichUI-owned frames, through a verified, supported API and with a clean fallback when Ellesmere UI is absent.
- Keep optional addon integrations optional. Missing supported addons should be reported neutrally, not as errors.
- Make common controls visible and understandable. Hide technical or rarely changed settings behind a simple, clearly labeled Advanced section; do not hide essential status, safety, or recovery actions there.

## Feature-specific principles

### Gear comparison

- Gear scores and upgrade indicators are guidance, not certainty or simulation-quality predictions.
- Reuse one evaluation implementation across supported interfaces, such as Blizzard bags and optional third-party bags.
- Account for class, specialization, level, slot compatibility, and relevant item properties only when reliable data is available.
- If specialization or item data is uncertain, fall back safely and make the limitation clear.
- Do not treat raw item level or a generic score as proof that an item is better.
- Keep the default presentation subtle, with additional explanation available on demand.
- Do not claim precise DPS, healing, survivability, or best-in-slot results without reliable evidence.

### Configuration sharing and backups

- Keep sharing and backup workflows distinct from persistent addon settings.
- Do not eagerly copy other addons' entire SavedVariables databases at login solely to support export or sharing. Snapshot only when the player explicitly requests an operation, and release temporary data when finished.
- WoW SavedVariables loading is controlled by the client. Do not claim that delaying access to a declared SavedVariables table prevents the client from loading it into memory.
- Keep exports limited to the data the player selected. Do not include Chronicle entries or unrelated personal data.
- Treat imported data as untrusted. Validate size, version, structure, value types, and required fields before changing saved data.
- Never deserialize imported content by executing it as Lua. Do not use `loadstring`, `load`, or equivalent dynamic code evaluation.
- Preview and confirm before applying another player's configuration or restoring a backup.
- Importing a portable backup should create a restore point; it must not silently apply it.
- Do not assume an addon can write arbitrary files or access the OS clipboard. Prefer a player-mediated export string using supported UI controls, and explain copy/paste limitations honestly.
- Avoid transmitting backup contents through public chat, addon messages, or external services unless the user explicitly requests a supported sharing flow.

### Journey Chronicle

- Treat the Chronicle as a private, per-character field ledger—not an achievement clone, quest guide, route planner, analytics system, or social broadcast tool.
- Record only meaningful events that the target client exposes reliably. Do not fabricate historical events or infer precise values from unreliable data.
- Keep automatic tracking bounded, event-driven, and free from duplicate entries.
- Make automatic event types and local notifications controllable by the player. Local feedback must never be sent to Party, Guild, or public chat.
- Preserve player-authored notes. Do not silently discard a player's notes to enforce automatic-entry limits.
- Keep Chronicle data separate from configuration sharing, profiles, recommendations, and restore points unless an explicit feature asks otherwise.
- Store timestamps as data and filter by timestamps, never by parsing formatted display text.
- Handle missing timestamps and unavailable API data without inventing values.
- If showing total played time, use an authoritative game API; do not derive it from Chronicle entries or wall-clock session time.
- Suppress false zone-arrival events during flight-path travel. Do not queue every intermediate zone crossed.
- A region-arrival treatment should feel like a brief RPG chapter card—“turning a page, not receiving an alert.” Avoid duplicating Blizzard or another addon’s zone banner, and respect reduced-motion settings.
- Keep notifications, sounds, and decorative effects subtle and optional.

### Chat commands

- Provide a concise help display when the primary TwichUI command is entered without arguments.
- Keep aliases consistent and route them through the same command parser.
- Keep command output local unless a command explicitly performs a user-requested communication action.
- Temporary diagnostics must remain isolated from normal sharing and messaging behavior, use harmless test data, and never claim end-to-end success without a real acknowledgement.

### Optional broker and addon integrations

- Inspect the actual supported APIs and target addon implementation before integrating.
- Prefer standard interoperable interfaces such as LibDataBroker when the target addon supports them.
- Verify how libraries are packaged; do not assume another addon provides a library at runtime.
- Do not build both a standard integration and a custom vendor-specific implementation without a demonstrated need.
- If an optional integration is unavailable, TwichUI must continue to load and its core feature must remain usable.
- Do not reach into unstable third-party internals when a documented integration API exists.

## Working with files

- Treat the repository as the source of truth. Do not edit the deployed copy in the WoW AddOns directory.
- Do not overwrite or delete user changes unrelated to the task.
- Do not include `Zone.Identifier` files, editor state, generated artifacts, local credentials, or machine-specific paths in commits.
- Keep generated or downloaded API references outside the addon source unless they are intentionally part of the project.
- Never put secrets, access tokens, or personal information in source files or Git.

## Performance and lifecycle

- Prefer clear, correct code. Do not add complex caching, pooling, or micro-optimizations without a demonstrated need.
- Avoid creating temporary tables, closures, or strings on high-frequency paths such as `OnUpdate`, rapid event handlers, or frequently repeated callbacks. If such a path needs optimization, explain the tradeoff and keep the code readable.
- Avoid per-frame `OnUpdate` work when an event, timer, or less frequent update can accomplish the same thing. If `OnUpdate` is necessary, keep its work small and throttle it where appropriate.
- Keep recurring work bounded. Do not create duplicate frames, timers, event registrations, or callbacks when an existing one can be reused.
- When adding timers, event handlers, frame scripts, or callbacks, consider their lifetime. Cancel or unregister them when the associated feature or UI object is disabled or no longer needed, if the API supports that.
- Avoid retaining frames, units, large tables, or other objects in long-lived tables or closures after they are no longer needed. Clear references when removing entries.
- Do not force garbage collection as a routine optimization. Do not claim there is a memory leak based only on total memory usage increasing; identify what is retained or repeatedly allocated.
- For performance-sensitive changes, state the expected hot path and validate the change with an available profiler or a reproducible in-game test. Do not add profiling overhead to normal operation unless requested.

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