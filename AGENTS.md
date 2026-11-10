# TwichUI: instructions for coding agents

A World of Warcraft addon for **WoW: Forever** (Lua 5.1): a focused interface companion. Spelling: TwichUI (never "Twitch"); the core folder is `!!!TwichUI/` (three `!`; single-quote such paths in the shell, `'!!!TwichUI/Core.lua'`).

The full rules are in [CLAUDE.md](CLAUDE.md) (and per-feature rules in [docs/dev-rules.md](docs/dev-rules.md)); read the sections a task touches. This file only repeats what must not be missed.

## Current work

The Reminders style upgrade: start at [docs/reminders-style-upgrade.md](docs/reminders-style-upgrade.md) (current state, milestones, verification, prompt) and the status entry in [STATUS_AND_BACKLOG.md](STATUS_AND_BACKLOG.md).

## Essentials

- Edit the repository, never the deployed AddOns copy, the live game install or real SavedVariables. Never edit `!!!TwichUI/Libs/`. Reference sources (`../wow-ui-source/`, `../reference_addons/`) are read-only.
- Do not commit, push, deploy, publish or change `.toc` `## Interface`/`## Version` unless asked. Never run `git clean`, reset or destructive checkout. Do not overwrite unrelated uncommitted work.
- Lua 5.1 only; `local` by default; follow the existing patterns, load order and SavedVariables names. Never `loadstring`/`load` untrusted data. Never automate protected gameplay actions or bypass Blizzard restrictions.
- Smallest complete change; no unrelated refactors, new dependencies or frameworks. Ask before material scope changes.
- Verify (from the repo root): `luac5.1 -p '<file>'` after each Lua edit; one test: `(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_x.lua)`; full suite `./tests/run.sh`; optional simulator `bash tools/simlab/smoke.sh` (bash, not zsh). Do not invent other commands.
- Label every claim: unit-tested, simulator-tested, screenshot-reviewed, real-client-tested or not tested. Never claim a check you did not run.
- Stop after two substantive failed approaches to one blocker: state the evidence, what is unknown and the smallest next action.
