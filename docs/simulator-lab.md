# Simulator lab

An optional way to run TwichUI's real addon code outside the game, in [wow-ui-sim](https://github.com/Osso/wow-ui-sim), and
take a screenshot of a real settings page. It sits beside the repository and is not part of any TwichUI package.

It complements `tests/run.sh`, which mocks the game's API. It replaces neither that suite nor testing in the game.

## What it is

| | |
|---|---|
| Tested on | Ubuntu 26.04, x86-64, WSL2, with no GPU device in the sandbox (software rendering through Mesa lavapipe) |
| Simulator | wow-ui-sim **v0.1.37**, asset `wow-ui-sim-v0.1.37-forever-linux-x86_64.tar.gz`, GPL-3.0-only |
| Forever profile | Fixed when the binary was compiled, so there is no flag for it. Reports `1.60.1 / 70532 / interface 16001` |
| Integrity | SHA-256 `66e9afa9…df8dfae`, GitHub's recorded asset digest. Upstream publishes no attestation or signature |
| Blizzard UI | Gethe `wow-ui-source`, branch `forever`, revision `ca8368f2f`, `1.60.1.70532`: the revision v0.1.37 pins |
| Addons loaded | `!!!TwichUI`, `TwichUI_Settings` and the lab's shim: only these, from an explicit root |
| Lab folder | `../wow-ui-sim-lab` (`WOWSIM_LAB` moves it). About 1 GB once used |

Needs `bwrap`, `rsync`, `git`, `curl`, `dpkg-deb`, Mesa's Vulkan drivers (`mesa-vulkan-drivers`) and a clone of
Gethe's `wow-ui-source` beside the repository (`SIMLAB_UI_SOURCE` moves it). Nothing is installed system-wide. The binary
wants Ubuntu 24.04's ICU 74 and ALSA, so `setup.sh` unpacks those two packages into the lab, checked by hash.

## Use it

```sh
tools/simlab/setup.sh            # once: downloads and builds the lab
tools/simlab/smoke.sh            # copies the working tree in, opens a page, constructs every page, judges the result
tools/simlab/interact.sh         # drives one real settings page through its controls, from a clean profile (below)
```

## What a result is evidence of

Every line a lab command prints is one of these, and nothing more. A pass at one level says nothing about the next.

| Level | `smoke.sh` | `interact.sh` | Means |
|---|---|---|---|
| Initialization | yes | yes | TwichUI's core loaded, its saved data came up, no hook failed |
| Page construction | yes (all pages) | yes (one page, and reopening it) | the window opened the page and built rows, with no captured error. **Not** "the page works" |
| Control interaction | no | yes, **handler-level** | a control's script ran when the simulator called it (see below). Not hit testing, focus, pointer or keyboard |
| State mutation | no | yes, in memory | `TwichUIDB`, the feature's model and what the controls show agreed after each change |
| Persistence | no | **no** | nothing is reloaded or read back from disk. Closing and reopening the window is not persistence |
| Screenshot | taken | taken | a file exists and is not blank. Whether it looks right is a person's call, and fonts are not the game's |
| Real client | no | **no** | nothing here has run in WoW: Forever |

Both commands also print what the result must be read with (the shim, the UI-version mismatch, the fonts, the client
behaviour that is not covered) before they judge.

Each run writes to `../wow-ui-sim-lab/artifacts/smoke-<time>/`:

| File | Holds |
|---|---|
| `settings.png` | the screenshot |
| `run.stdout` | the addon load summary and the frame tree of TwichUI's frames |
| `run.stderr` | the full startup log, the fixture's `SIMLAB` lines, and every `Lua error:` |
| `pages.stdout`, `pages.stderr` | the same for the all-pages run |

`smoke.sh` takes `SIMLAB_PAGE` and `SIMLAB_TITLE` for another page, `SIMLAB_SHIM=0` to leave the shim out, and
`SIMLAB_ASSETS=0` to hide the game. For anything else, `tools/simlab/sim.sh` takes the simulator's own arguments:

```sh
tools/simlab/sim.sh --no-addons --no-saved-vars lua-errors
```

A PASS needs more than a clean exit: the real page opened through `R:OpenSettings`, finished fading in and constructed rows, no
Lua error was raised, none of TwichUI's textures were lost, the window holds real pixels, and every page constructed.
Errors TwichUI catches do count, because `R.Fault` hands them to the error handler the simulator watches. It ends
`PASS (initialization and construction only)`: that is all it is.

## The interaction scenario

```sh
tools/simlab/interact.sh         # about 20 s here; SIMLAB_SHIM=0 and SIMLAB_ASSETS=0 work as for smoke.sh
```

**The page:** Notifications → Appearance (`notificationsLook`, `TwichUI_Settings/pages/Notifications.lua`, saved by
`modules/NotifyLook.lua` in `TwichUIDB.ui.notifyLook*`). It is the first one because it is all appearance (no gameplay
action, no combat rule, no protected frame, no other addon, nothing sent), it has one of each control (drop-downs, a
checkbox, sliders with a range) and it has a locked state to test: a card's settings are greyed out until "Give this
card its own look" is on. It applies changes at once, so there are no drafts and no Apply or Cancel to test.

**How controls are driven.** The simulator has no input injection in headless mode: its CLI offers `--exec-lua` and
nothing else, and `A_Admin` has `SetMousePosition`, `SetMouseOverFrame` and key-state setters but no click or key
sender (read from its key list; strings in the binary name mouse events, but no headless command reaches them). So
every interaction is **handler-level**,
through the controls TwichUI really built (`UI.View(page).rows[id]`, ids from the settings' own variable names):

| To do | The scenario calls | Runs |
|---|---|---|
| click a checkbox or a drop-down | `Button:Click()` on the control | its `OnClick` script |
| pick a drop-down entry | `Click()` on the entry in the shared list (found by its value) | the entry's `OnClick`, then the row's `onPick` |
| end a slider drag | `Slider:SetValue(n)` | its `OnValueChanged` |
| type a number | `EditBox:SetText(t)`, then the box's own `OnEnterPressed` script | the clamp in `Widgets.lua` |

That shows a control's handler does what it says. It does **not** show a player can reach the control: hit testing,
pointer coordinates, focus, keyboard navigation, Tab order and a control hidden behind something are untested.

**What it does,** from a new empty install (`--no-saved-vars`, an empty lab WTF folder; nothing of this page saved):

1. *initial*: the page opens; the scope drop-down, text size (100, range 80–140) and outline show their defaults; the "own look" row is hidden.
2. *choose a card*: pick "Zone arrival" in the drop-down. Choosing saves nothing; the row appears; the card's controls are locked, and typing 120 into the locked box is refused.
3. *toggle own look*: click the checkbox. The card gets a complete saved look; the shared look is not written; the controls unlock.
4. *slider and number box*: typing 500 saves 140 and 10 saves 80; dragging to 120 saves 120; typing `abc` leaves 120; the model itself refuses 500; the shared look stays at 100.
5. *dropdown*: pick "Thick outline"; it is saved for the card only.
6. *close and reopen*: close the window, change a value behind its back, reopen. The same drawn page is reused (no second copy, same rows) and shows what is in memory.

Expected values are typed from the page's source, not read from the code under test. Controls are found by their
setting ids, never by their text or position. It adds no production code.

**Four launches, each from a freshly emptied root:** the scenario with a screenshot, the same again (the saved result
and every check must be identical), the first step alone with a screenshot, and the scenario with one expectation made
wrong on purpose (`slider-clamp-max: typed 500 saved as`), which must fail on that check and on no other. The command
exits 0 only if all of that holds and the repository's `git status --ignored` is unchanged. Each run writes
`after.png`, `before.png` (both scrolled, by the window's own `Navigate`, to the Text size row), and `a/a2/before/wrong`
`.stdout`/`.stderr` to `../wow-ui-sim-lab/artifacts/interact-<time>/`.

**Not tested here:** reload persistence (nothing is written or read back), the colour swatches and their picker, the
preview buttons and the cards they show, the other 48 pages' controls, drafts (this page has none), search reveal and
a packaged install.

**Simulated time is budgeted (2.5 s).** The sample character is in a party, so TwichUI sets its 3 second "hello"
timer (`setup/Group.lua`) at startup. When the manual clock passes it, the hello goes out through the simulator's
addon-message path and raises `string at argument 2 is not valid UTF-8` inside `Blizzard_ScriptErrors`' error-data code,
reached from `ChatThrottleLib`'s protected send. It looks like the error handler failing on an error from the send; the
original error was not seen, and whether the fault is the simulator's or in a payload TwichUI sends is unknown. Other Blizzard timers then fail on `C_VoiceChat.CanAccessSettings`, which the simulator does not
supply. These are lab gaps, so the scenario stays under the first timer and fails loudly if it ever goes over, rather
than ignoring Lua errors. Changes in the page are synchronous and need no simulated time; only the window's fade does.

## How it is isolated

`sim.sh` runs everything under `bwrap`. The filesystem is read-only apart from the lab's own home, cache, data and
artifact folders; the real home folder (so the repository too) is hidden; C: is hidden; there is no network. The game
appears only for runs with game assets, and then only its install folder, read-only.

That matters here: the binary looks for the game at `/mnt/c/Program Files (x86)/World of Warcraft` by itself, whatever
`HOME` says. Run it through `sim.sh`, not directly. The simulator cannot see the repository, so `smoke.sh` copies the
addons into `roots/twichui`, the only addon root it is given. `--no-saved-vars` and an empty lab `wtf/` mean every run starts
as a new install, with synthetic state only.

Checked on 2026-10-30 by running a probe script in the sandbox (`SIMLAB_BIN`): the repository path does not exist
(`/home/rich/dev/personal/TwichUI` is absent; only the lab's own folders are mounted under it), C: is empty without
`SIMLAB_ASSETS=1`, a TCP connect fails ("Network is unreachable"), writes to the lab's `release/`, `roots/` and
`fixtures/` fail with "Read-only file system" while `artifacts/` accepts them, the game install is read-only when shown,
the environment holds only the variables `sim.sh` sets, and nothing a probe wrote under the real home landed on the
machine. Each launch of `smoke.sh` and `interact.sh` empties and refills the addon root first, refuses to start if the
lab's WTF folder holds files, and checks the shim is in the root exactly when `SIMLAB_SHIM` says; `interact.sh` also
checks no artifact appears in the root and the repository's `git status --ignored` is the same before and after.

## Game assets

Optional for logic, required for the look. By default the simulator reads Blizzard's textures and fonts from the local
game's CASC data, read-only. It extracts what it uses into the lab's `xdg/cache`, so **screenshots and the lab hold
Blizzard's art: keep them local**.

`SIMLAB_ASSETS=0` needs no game at all, and a PASS there covers logic only. `Interface\Buttons\WHITE8x8` goes missing, which
removes TwichUI's solid fills, and the fallback font wraps text differently.

## Known limits

- **The shim.** `shim/!!!!SimLabShims` adds `C_ChatInfo.RegisterAddonMessagePrefix` and `IsAddonMessagePrefixRegistered`,
  which the game documents and v0.1.37's Forever profile lacks. Without them `setup/Share.lua`, `pins/Sync.lua`,
  `pins/Ping.lua` and `npcs/Share.lua` stop part way as bundled AceComm loads: 8 Lua errors, though all 49 pages still draw.
  The shim only remembers names. It proves nothing about addon messaging, and it refuses to load once the simulator has them.
- **The UI is behind the client.** The simulator pins `70532`. The game moved to `1.60.1.70707`, and its own sync then
  stops with `Gethe version mismatch`, which is why `setup.sh` builds the cache as upstream's Dockerfile does. So Blizzard's
  UI code is `70532` while the art comes from the installed `70707`, and this release carries no `wow-cli` to sync with.
- **TwichUI's own fonts are not drawn.** `font.rs` registers only the game's fonts and draws any other path in Friz
  Quadrata. `Cinzel-SemiBold.ttf` is named in the frame tree but not on screen, which is why the title shows lowercase
  letters Cinzel does not have. Text measured in addon fonts is not what the game would measure.
- **Text rendering differs.** Screenshots are for structure, layout and missing pieces, not fine visual judgement. A
  Blizzard "Issue Report" button draws over the window; whether the game stacks them the same way is unverified.
- **Runs are not pixel-identical.** Upstream's sample character gets a varying set of buffs, so comparing two screenshots
  needs a crop or a mask; a few text pixels inside the window differed between otherwise identical runs too.
- **The simulator patches Blizzard's UI as it starts** (the `[Workarounds]` lines in the log), and models secret values and
  much of the API by inference. Its own documents say this is not native conformance.
- **Not covered:** combat lockdown, taint and secure actions, sending or receiving addon messages, saved data surviving a
  reload, EllesmereUI and other optional addons, real pointer and keyboard input, and a packaged install. Controls are
  exercised for one page only, at handler level; the all-pages test proves each page constructs, not that its controls work.
- **The sample character is upstream's:** a level 70 paladin with a Retail-era fixture, not Forever gameplay data.
- **Upstream's `master` documents are ahead of this tag.** They describe `wow-cli` and spell data in Forever packages; the
  v0.1.37 archive has neither. Read the tag, not `master`, when changing versions.

## Baseline, 2026-10-30

Run against the final files (after the interaction scenario was added), from a clean tree apart from the two untracked
paths this lab adds. Simulator v0.1.37, `wow-ui-sim-lab` as built by `setup.sh`.

| Command | Exit | Result |
|---|---|---|
| `bash -n tools/simlab/{setup,sim,smoke,lib,interact}.sh` | 0 each | syntax only |
| `python3 -I` parse of `verdict.py`, `interact_verdict.py` | 0 each | syntax only |
| `shellcheck` | not run | not installed, and not installed for this (no approval to install system tools) |
| `tests/run.sh` (project offline suite) | 0 | 141 passed, 0 failed |
| `tools/simlab/smoke.sh` | 0 | `PASS (initialization and construction only)`: page `qol`, 49 of 49 pages constructed, no Lua error; about 12 s |
| `SIMLAB_SHIM=0 tools/simlab/smoke.sh` (negative control) | 1 | FAIL on "no Lua error": 8 errors from `AceComm` loading without the shim; the root held no shim afterwards |
| `SIMLAB_PAGE=nosuchpage tools/simlab/smoke.sh` (negative control) | 1 | FAIL: the page shown was `overview`, no rows, title not in the tree |
| `tools/simlab/interact.sh` | 0 | `PASS (handler-level interaction and in-memory state only)`: 67 checks (8 initialization, 9 construction, 5 interaction, 45 state), 1.8 s simulated, no Lua error; the second run's checks and saved result identical; about 22 s |
| `SIMLAB_SHIM=0 tools/simlab/interact.sh` (negative control) | 1 | FAIL on "no Lua error" (the same 8 load errors); the scenario's own checks still passed |
| `interact.sh`'s built-in negative control (`slider-clamp-max: typed 500 saved as` made wrong) | part of the above | failed on exactly that check; the other 66 passed |

Also tried once, by hand, outside the lab's commands: breaking the lab's copy of `NotifyLook.lua` (text size limit
140 → 130) made 4 checks fail; making `SetOwn` do nothing made 22 fail. Neither touched the repository.

Screenshots from the final run (`before.png`, `after.png`) were looked at: the page shows Text size 100 and "Shadow
(default)" before, 90 and "Thick outline" after, and the "Main text color" row is gone after (the Zone arrival card
has no main text). That says the structure and the changed values drew; with the fonts not drawn (below) and Blizzard's
"Issue Report" button over the window, it says nothing about how the page looks in the game.

## Remaining blockers

- **In-game, still required:** that the page's controls can be reached and used by pointer and keyboard; that the
  saved values survive a reload; how the page and its previews look in the real client's fonts; everything under
  "Not covered" above. Nothing in this lab replaces those.
- **Two APIs are shimmed** (`C_ChatInfo.RegisterAddonMessagePrefix`, `IsAddonMessagePrefixRegistered`). Filing them
  upstream is not done (it is outward-facing and needs your approval).
- **TwichUI's own fonts are not drawn** by v0.1.37, so text measurements and wrapping here are not the game's.
- **Simulated time is capped at 2.5 s** by the group-hello failure above; a scenario that needs the clock past 3 s needs
  that cause understood first (simulator or TwichUI payload).
- **Only one page's controls are exercised.** Reload persistence, the swatches, previews and other pages' controls are not.
- **UI source and client differ** (70532 against 70707), and the simulator patches Blizzard's UI as it starts.

## Moving to a newer simulator

Change `TAG`, `PACKAGE_SHA256`, `UI_REVISION` and `UI_VERSION` in `setup.sh` and the release name in `sim.sh`, then run
`SIMLAB_SHIM=0 tools/simlab/smoke.sh`. If the simulator has gained the two functions, the shim's `assert` says so; delete it.

## Remove it

```sh
rm -rf ../wow-ui-sim-lab   # everything the lab made, including its copies of Blizzard's art
rm -rf tools/simlab docs/simulator-lab.md
```

The first line does not touch the repository, the game or `wow-ui-source`. Nothing in the addons refers to the lab.
