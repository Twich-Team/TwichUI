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
tools/simlab/diagnose.sh         # the clock over a 12 s window: baseline, solo, grouped, and the addon-message contract (below)
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

`diagnose.sh` is not a test of a page. It measures how the clock, a party and the simulator's addon-message call behave (see
"Delayed failures"), and it reports what it found by kind rather than as one pass:

| Kind | Means | Example here |
|---|---|---|
| Passed behavior | a check's expectation held | solo: no group, nothing sent in 12 s |
| Unsupported behavior | the simulator does not answer an API the game does | `C_VoiceChat.CanAccessSettings` |
| Known delayed failure | an error that happens later in the window, classified by what it is | the simulator refusing the group hello's bytes |
| Shimmed behavior | a lab stand-in answered | the two prefix-registration functions (names only) |
| Excluded subsystem | not run or not modelled, so nothing is claimed | message delivery and receipt, voice chat, secure actions |

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

1. *initial*: the character leaves the simulator's sample party and the solo state is checked; the page opens; the scope drop-down, text size (100, range 80–140) and outline show their defaults; the "own look" row is hidden.
2. *choose a card*: pick "Zone arrival" in the drop-down. Choosing saves nothing; the row appears; the card's controls are locked, and typing 120 into the locked box is refused.
3. *toggle own look*: click the checkbox. The card gets a complete saved look; the shared look is not written; the controls unlock.
4. *slider and number box*: typing 500 saves 140 and 10 saves 80; dragging to 120 saves 120; typing `abc` leaves 120; the model itself refuses 500; the shared look stays at 100.
5. *dropdown*: pick "Thick outline"; it is saved for the card only.
6. *close and reopen*: close the window, change a value behind its back, reopen. The same drawn page is reused (no second copy, same rows) and shows what is in memory.
7. *time passes*: the clock runs to the 12 s window (below). No send was attempted, the saved look and the page are unchanged.

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

**Simulated time.** The last step, "time passes", runs the clock to a declared window (12 s, `SIMLAB_WINDOW`), solo, and
checks that nothing was sent and the page is unchanged. The scenario used to stop at 2.5 s to stay clear of two errors; both
are now classified instead (next section), and the only limit left is a 30 s resource guard in `scenarios/lib.lua`. Changes
in the page are synchronous and need no simulated time; only the window's fade does.

## Delayed failures

Two errors appear once the simulated clock passes a few seconds. Neither is hidden: the log keeps both, and
`known_failures.py` judges every `Lua error` in it by **what it is** (message, and stack where the message is too general),
never by when it happened. A run permits only the rules it names. An error that matches no rule fails the run, a classified
error the run does not permit fails it, and a classified error a run requires but never sees fails it too (the rule is stale).
`diagnose_verdict.py` also feeds the classifier four synthetic logs to show it can fail for each reason, and applies the
settings scenario's permit set to the real grouped log to show that going solo there hides nothing (the hello is rejected).

```sh
tools/simlab/diagnose.sh                  # four launches, about 15 s: contract, baseline, solo, grouped (SIMLAB_WINDOW=12)
tools/simlab/interact.sh                  # the settings scenario, solo, over the same window
tools/simlab/sim.sh --no-saved-vars --no-addons --exec-lua '@<fixture>' dump-tree --visible-only   # a single launch, by hand
```

### Group state

The simulator is solo while addons load, then adds its sample party (a level 70 paladin with four others) after
`PLAYER_ENTERING_WORLD` (`GROUP_ROSTER_UPDATE`, 5 members, about 0.1 s after the login event). So `A_Admin.SetPartySize(0)`
cannot make the start solo: TwichUI sees the party arrive, and the scenario then calls `Lab.Solo()`, which leaves it and checks
`IsInGroup()`, `IsInRaid()`, `GetNumGroupMembers()`, the `party1..4` units and TwichUI's own `Group.Members()`. That is "left the
party before the timer", not "never grouped". The 3 s hello timer then still runs out and sends nothing, because
`Group.lua`'s `Broadcast` asks `IsInGroup()` when it fires; the observer counts zero attempts. The grouped diagnostic keeps the
party on purpose.

### The group hello (`addon-message-invalid-utf8`)

Call path, read from source and confirmed by the observer: `Group.lua:293` timer (3 s after the party arrives) →
`G:SayHello` → `Broadcast` → `SH.SendControl` → `Share.lua` `Send`: `Encode` = `LibSerialize:Serialize` →
`LibDeflate:CompressDeflate` (level 5) → `EncodeForWoWAddonChannel`, then
`AceComm:SendCommMessage("TwichUISetup", text, "PARTY", nil, "NORMAL")` → `ChatThrottleLib` `PerformSend`, which calls
`xpcall(C_ChatInfo.SendAddonMessage, CallErrorHandler, prefix, text, "PARTY", nil)`.

| Observed (grouped run) | |
|---|---|
| Arguments | `string, string, string, nil`; prefix `TwichUISetup`, chat type `PARTY`, target none |
| Payload | 29 bytes, the message `{t="hello", v=<version>, p=2, to="*"}`: a version and a protocol number, nothing about the player |
| Bytes | `6374132a60152a09ca48cdc9c9572ac917d2122a0b32d433d0330102fc`; the first invalid UTF-8 byte is the 9th (`ca 48`) |
| Stages | Serialize: 26 bytes, valid UTF-8. CompressDeflate: 28 bytes, not UTF-8, contains NUL. EncodeForWoWAddonChannel: 29 bytes, not UTF-8, no NUL |
| Result | `string at argument 2 is not valid UTF-8`, raised by the call itself (the same bytes under a direct `pcall` fail identically) |
| Same library path, ASCII `hello` | accepted. The refusal is about the bytes, not ChatThrottleLib or AceComm |
| Same run, `TwichUIPins` message | 12 bytes, all below 0x80, so valid UTF-8 and accepted. Whether a payload passes depends on its bytes |

**Not a handler failure.** The earlier note put the error "inside `Blizzard_ScriptErrors`". That is only where the stack is
printed: `ChatThrottleLib` sends under `xpcall` and hands the error to the error handler, whose `GetErrorData` writes the
trace. The message comes from `SendAddonMessage`.

**The simulator's rule** (`scenarios/message_contract.lua`, no addon loaded, 22 checks): for 12 byte strings (ASCII, 2- and
4-byte sequences, U+10FFFF, embedded NUL, a lone continuation byte, `0xFF`, a truncated sequence, two overlong forms, a
surrogate, a value above U+10FFFF) the simulator accepts exactly the ones that are strict UTF-8, and names the argument
(1, 2, 3 or 4). `SendAddonMessageLogged` does the same. That is the host binding's string-parameter rule, not a check of
addon messaging. The simulator is a binary (no source here), so this is measured, not read.

**The game's rule is not established.** The Forever API document types `message` as `cstring` and calls it a "text payload"
(`SendAddonMessageLogged` adds "intended for plain text payloads"); no local file defines `cstring`'s encoding. `LibDeflate`
documents `EncodeForWoWAddonChannel` as guaranteeing only "no NUL" and contrasts it with its chat-channel codec, which
encodes every byte above 127 because `SendChatMessage` errors on incomplete UTF-8: so the library's author treats the addon
channel as taking arbitrary non-NUL bytes. A reference addon (`NaowhForever_Utilities/InstanceTracker`) sends that encoding.
That is the ecosystem's convention, not proof for WoW: Forever.

**Classification: simulator string-rule difference; real-client contract unverified (insufficient evidence for a
production defect).** TwichUI builds the payload the way its encoder documents. No TwichUI code changed, and nothing was
stripped, re-encoded or turned into a no-op. If you want it settled, the decisive test is one line in the game, in a party,
which says what the game does with a non-UTF-8 message (it shows the call is accepted or refused, not that anyone receives it):
`/run print(pcall(C_ChatInfo.SendAddonMessage, "TwichUIProbe", "a\200b", "PARTY"))`.

### The voice-settings call (`voice-settings-unsupplied`)

Scheduled by Blizzard's own `Blizzard_SettingsDefinitions_Shared/Audio.lua:657-669`: `C_Timer.NewTicker(5, TryInitVoiceSettings)`
calls `C_VoiceChat.CanAccessSettings()` until it returns true, "no timeout", because the voice proxy process may not be up yet.
It happens with no addon loaded (the baseline launch, `--no-addons`), at about 4.5 s and 9.5 s after the script starts. The
Forever UI source calls it and the API document lists it returning a non-nil bool, so the profile should have it; the
simulator has the function but raises `settings access has not been supplied`, and `A_Admin` has no setter for it. The UI
revision is not a factor: the simulator's cached `Audio.lua` is byte-identical to `wow-ui-source` at `ca8368f2f` (the 70707
client's file cannot be compared here). **Classification: unsupported API in the simulator, Blizzard-owned timer, no addon
involved.**

It is deliberately **not shimmed**. The function exists, so a stand-in would override a native implementation (the lab's rule
is that a shim never does), and the classification already keeps both the error and the evidence. By Blizzard's comment the
real function answers `false` until the proxy is up; if a silent run is ever wanted, an opt-in shim returning `false` that
first asserts the native refusal, with this unshimmed run kept as the control, is the way. That is a decision, not made here.

### What the 12 s window exercises

The clock runs 240 steps of 0.05 s over 12 simulated seconds, with a marker every 0.5 s. It crosses the group hello (the 3 s
timer) and two voice ticks. It does **not** reach the 20 s direct-message probe timeout or the 60 s transfer timeout in
`setup/`, does not exercise the login hello (6 s; the character is not grouped at login), and the other
timers in the addons were not enumerated. It is a longer window, not exhaustive timer coverage.

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
- **Not covered:** combat lockdown, taint and secure actions, delivering or receiving addon messages (`diagnose.sh` observes the
  simulator accepting or refusing a call, nothing more), saved data surviving a
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

## Baseline, delayed-failure pass, 2026-10-30

Run against the final files, after the first baseline above (whose `interact.sh` row, 67 checks in 1.8 s, is superseded by
the one below). Production code unchanged.

| Command | Exit | Result |
|---|---|---|
| `tools/simlab/smoke.sh` | 0 | `PASS (initialization and construction only)`, unchanged: 49 of 49 pages, no Lua error |
| `tools/simlab/diagnose.sh` | 0 | contract 22 checks; baseline 3 (no addon: voice error present, nothing sent); solo 10 (state verified solo, no send in 12 s); grouped 18 (hello attempted at about 3 s, refused, the one classified error besides voice); the permit-set and four classifier controls pass; about 15 s |
| `tools/simlab/interact.sh` | 0 | `PASS`: 74 checks (10 init, 9 construct, 5 interact, 50 state), 12.1 s simulated, solo; only the classified voice error in the log; second run identical; the wrong-on-purpose run failed on exactly its check; about 23 s |
| `SIMLAB_SHIM=0 tools/simlab/interact.sh` (negative control) | 1 | FAIL on the unclassified AceComm load error, as before |
| `SIMLAB_SHIM=0 tools/simlab/diagnose.sh` (negative control) | 1 | FAIL: solo and grouped hit the same unclassified load error |
| `tests/run.sh` | 0 | 141 passed, 0 failed |
| `python3 -I` parse of the three verdict scripts and `known_failures.py`; `bash -n` on the runners | 0 | syntax only; `shellcheck` is still not installed |

Window: 12 simulated seconds in 0.05 s steps. Classified errors seen: `voice-settings-unsupplied` in every long run (first
printed after t=4.3 to 4.5 s), `addon-message-invalid-utf8` only in the grouped run (after t=2.5 s).

## Remaining blockers

- **In-game, still required:** that the page's controls can be reached and used by pointer and keyboard; that the
  saved values survive a reload; how the page and its previews look in the real client's fonts; everything under
  "Not covered" above. Nothing in this lab replaces those.
- **Two APIs are shimmed** (`C_ChatInfo.RegisterAddonMessagePrefix`, `IsAddonMessagePrefixRegistered`). Filing them
  upstream is not done (it is outward-facing and needs your approval).
- **TwichUI's own fonts are not drawn** by v0.1.37, so text measurements and wrapping here are not the game's.
- **Two delayed errors are classified, not fixed** ("Delayed failures"). The voice-settings one is the simulator's and
  Blizzard's timer; the group hello's refusal is the simulator's string rule, and whether the game would accept the same
  bytes is **unverified**: it needs the one-line in-game check given there. A scenario can now run the clock over a window,
  but only with those two rules permitted; any third error fails the run.
- **A grouped start cannot be solo from the beginning:** the simulator adds its party after `PLAYER_ENTERING_WORLD`, so a
  "solo" scenario is "left the party", and the login hello (6 s) is never exercised.
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
