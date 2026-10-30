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
bash tools/simlab/tests/lab_guard.sh   # the lab-path safety check's rejection paths, in disposable folders (below)
```

Run the scripts with bash (`tools/simlab/x.sh` or `bash tools/simlab/x.sh`). Under zsh they stop before creating anything.

## Coverage summary (milestone closed 2026-10-30)

**What works.** The real `!!!TwichUI` and `TwichUI_Settings` code loads in the simulator from a clean install; all 49 described
settings pages *construct* without a captured Lua error; one page (`notificationsLook`) is driven through its controls at
handler level with state checks, solo, over a 12 s simulated window; the group clock, the addon-message contract and the
login path are observed (`diagnose.sh`); two known simulator errors are classified, and any third fails the run.

**49 of 49 pages is construction, not 49 tested pages.** Only one page's controls are exercised. The other 48 are known to
build and show their rows, nothing more.

**Commands, and when to run them**

| Command | Use it for |
|---|---|
| `tools/simlab/smoke.sh` | After touching settings pages, Kit/widgets, the TOC or load order: does everything still load and construct (about 12 s) |
| `tools/simlab/interact.sh` | After touching `NotifyLook`, the settings Kit or the controls it uses: handler-level behaviour and in-memory state (about 23 s) |
| `tools/simlab/diagnose.sh` | Only for group/share/timer work: the clock window and message contract (about 15 s) |
| `tests/run.sh` | The project's offline suite; still the main check, and the only one for most logic |
| `bash tools/simlab/tests/lab_guard.sh` | After touching `lib.sh`, `setup.sh` or `sim.sh` |

For ordinary feature work, `smoke.sh` is the useful one (it catches load-order and construction errors the mocked suite
cannot), plus `tests/run.sh`. `interact.sh` and `diagnose.sh` matter only for the areas above.

**Accepted limitations.** Addon fonts fall back to a game font ("Fonts" below, with the investigation). Addon-message and
voice APIs behave as documented under "Delayed failures". Interaction coverage is handler-level. The setup wizard, reload
persistence and real pointer/keyboard input are untested here.

**Still requires the real client:** combat lockdown, taint and secure actions, addon-message delivery, saved data across a
reload, how anything looks (fonts, wrapping, art), real input, EllesmereUI and other addons, the packaged install.

## Cleanup safety

The only deletion in the tooling is `simlab_stage`'s `rm -rf` of the addon root (`$LAB/roots/twichui`); `setup.sh` also removes
its own `mktemp` staging folder. Since 2026-10-30 `lib.sh` (`simlab_check_lab`) runs before anything is created or deleted:

- `LAB` must be absolute, non-empty, and is resolved with `realpath -m` (so `..` and symlinks cannot disguise it).
- Refused: `/`, the home folder, the repository (or anything inside it), the game install (`SIMLAB_WOW`), and any folder
  that contains home, the repository or the game install.
- Runners (`smoke`, `interact`, `diagnose`, `sim`) additionally need the marker `$LAB/.simlab-lab` (text
  `twichui-simlab-lab 1`, a regular file, not a link). `setup.sh` writes it and may adopt a folder only if it is new, empty,
  already marked, or holds nothing but the folders setup makes (`downloads release deps home artifacts fixtures roots wtf xdg`,
  and `env.sh` from an early lab). A lab built before the marker existed needs `setup.sh` run once (or the marker written).
- The root's deletion also requires `ROOT` to be exactly `$LAB/roots/twichui`, with `roots` and the root real folders, not links.
- The scripts refuse to start under zsh or another shell (`BASH_SOURCE`/`BASH_VERSION` empty): the earlier wrong-folder
  incident was zsh resolving `BASH_SOURCE` to nothing.

`tests/lab_guard.sh` checks 28 accept/refuse paths and the zsh refusal, using only `mktemp` folders (home and the game
install are replaced by temporary stand-ins; the real protected places are never deleted from or written to).

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

1. *initial*: the character is solo (`WOW_SIM_NO_PARTY=1`) and that state is checked; the page opens; the scope drop-down, text size (100, range 80–140) and outline show their defaults; the "own look" row is hidden.
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
tools/simlab/diagnose.sh                  # five launches, about 20 s: contract, baseline, solo, grouped, login (SIMLAB_WINDOW=12)
tools/simlab/interact.sh                  # the settings scenario, solo, over the same window
tools/simlab/sim.sh --no-saved-vars --no-addons --exec-lua '@<fixture>' dump-tree --visible-only   # a single launch, by hand
```

### Group state

By default the simulator is solo while addons load, then adds its sample party (a level 70 paladin with four others) after
`PLAYER_ENTERING_WORLD` (`GROUP_ROSTER_UPDATE`, 5 members, about 0.1 s after the login event). Two ways to a solo character,
and they test different things:

- **Never grouped:** `WOW_SIM_NO_PARTY=1` (an option the binary names; `interact.sh` sets it). Observed with the timer
  probe: `n=0` at `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD` and the roster update after it, no hello timer scheduled, no send.
- **Left the party:** the `solo` launch of `diagnose.sh` keeps the default party and calls `Lab.Solo()`, which leaves it
  (`A_Admin.SetPartySize(0)`, which fires `GROUP_ROSTER_UPDATE`). TwichUI saw the party arrive, its 3 s hello timer then
  still runs out, and nothing is sent because `Group.lua`'s `Broadcast` asks `IsInGroup()` when it fires. That exercises
  TwichUI's own check.

Either way `Lab.Solo()` checks `IsInGroup()`, `IsInRaid()`, `GetNumGroupMembers()`, the `party1..4` units and TwichUI's own
`Group.Members()`. The grouped diagnostic keeps the party on purpose.

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
stripped, re-encoded, replaced or stubbed. Nothing in this lab sends a message to anyone or receives one.

**What a real-client probe could and could not show.** These are four different claims, and one `pcall` supports only the first:

| # | Claim | What shows it |
|---|---|---|
| 1 | The API call was accepted or refused | the call's return value or error, on one client. This is all `pcall(C_ChatInfo.SendAddonMessage, …)` shows, and "accepted" means the client took the call, not that anything left the machine |
| 2 | The message was actually transmitted | not visible from the sender; needs a receiver, or the server's view |
| 3 | The message was actually received, byte for byte | a second listener (another client, with the prefix registered by `C_ChatInfo.RegisterAddonMessagePrefix`) reading the payload from `CHAT_MSG_ADDON` and comparing the bytes |
| 4 | TwichUI decoded it (a round trip) | that receiver running TwichUI's own decode on the received text. TwichUI's built-in self-test route (`LOOP`) never goes through the game, so it does not count |

A probe for claim 1 alone, **proposed and not run, waiting for approval**: prefix `TwichUIProbe` (registered by no addon, so
no addon reads it), payload the three bytes `61 c8 62` (`"a\200b"`, not valid UTF-8), chat type `PARTY` (so it needs a
group), one call, nothing else. Expected side effects: none in TwichUI; the message goes to the server and counts toward the
addon-message throttle; the other party members' clients receive an addon message nobody handles, and an addon that logs all
addon traffic would show it. The result is the call's return value or error text. Claims 2 to 4 need two clients and a
separate, approved plan, which is worth designing only if claim 1 shows the game accepts the bytes.

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

### What the 12 s window exercises, and event paths, not elapsed time

The clock runs 240 steps of 0.05 s over 12 simulated seconds, with a marker every 0.5 s. A longer clock does not reach a
timer whose scheduling event never happened, so coverage is stated per path, not per second. For the 6 s login hello
(`setup/Group.lua:301-306`, a `PLAYER_ENTERING_WORLD` handler that schedules `C_Timer.After(6, …)` only when `isLogin or
isReload` **and** `IsInGroup()`), observed with a throwaway observer addon loaded before TwichUI (not kept in the repository):

| Question | Answer in the simulator's own startup |
|---|---|
| Scheduling event | `PLAYER_ENTERING_WORLD(true, false)` |
| Did it occur? | yes, about 0.1 s before the party appears |
| Was the timer scheduled? | **no.** `IsInGroup()` was false when the handler ran (the simulator adds its party after this event), so the condition failed and `Group.lua:303` never ran |
| Cancelled or suppressed? | neither; there was nothing to cancel. The rate limit in `SayHello` was not involved |
| Did its callback run? | no |
| Was a send attempted? | not from this path. The grouped run shows exactly one hello in the window (a check), from the 3 s timer that `GROUP_ROSTER_UPDATE` schedules (`Group.lua:293`) |

So the path is unreached because of the order of the simulator's fixture, not because the window was too short. The `login`
launch of `diagnose.sh` reaches it on purpose: after startup, while grouped, the **lab** fires `PLAYER_ENTERING_WORLD(true,
false)` (the log says SYNTHETIC). The 6 s timer is then scheduled, its callback runs, and a second hello is attempted about
6 s later and refused like the first. That shows the handler's logic when the event arrives with those arguments and a
group; it does not show that the game delivers that event in that state at a real login.

What the window does cover: the 3 s group hello and two voice-settings ticks (about 4.5 s and 9.5 s). Because the lab starts
from an empty profile, TwichUI also treats it as a **first install** and, a few seconds in (`Onboarding.lua` schedules it,
`LayoutsLauncher.lua` waits `CONTINUE_AFTER = 3`), tries to open the layout wizard. The wizard's companion addon is not in
the lab root, so TwichUI prints "couldn't open the layout setup: its folder, TwichUI_LayoutWizard, is missing" in chat (visible
in `after.png`, absent from the 0.7 s `before.png`). That is a chat notice, not a Lua error, so the classifier does not see
it; the wizard itself is untested here. It is a path the earlier 1.8 s runs never reached. It does **not** reach
the 20 s direct-message probe timeout or the 60 s transfer timeout in `setup/`, and the other timers in the addons were not
enumerated. It is a longer window with two named paths, not exhaustive timer coverage.

### Reading a PASS

The scenarios end in one of two different sentences, and they are not interchangeable:

- `PASS (… no runtime errors in the log)`: every assertion held and the log holds no Lua error.
- `PASS WITH KNOWN SIMULATOR LIMITATIONS (…)`: every assertion held, and the log still holds the classified simulator errors
  printed above it. This is what `interact.sh` and `diagnose.sh` print today.

An ordinary scenario (`interact.sh`) **permits** the voice error and never requires it, so it does not break if the simulator
starts answering that call; it still fails on any other error, and on the hello error, which it does not permit. Only a
dedicated compatibility diagnostic (`diagnose.sh`) **requires** a known error. When one never shows, the run ends
`REVIEW NEEDED` (exit 1, "nothing else failed"): the simulator changed, so look at `known_failures.py` and these notes
and remove or amend the rule. That is a prompt to review, not a functional failure.

## Fonts

TwichUI ships 12 TrueType fonts in `!!!TwichUI/media/fonts/` (Alegreya, Alegreya Sans, Barlow Semi Condensed, Cinzel, Spectral)
and names them by `Interface\\AddOns\\!!!TwichUI\\media\\fonts\\…`. In the simulator **none of them is ever loaded.** `SetFont`
returns `true` and `GetFont` returns the path, but the text is measured and drawn in Friz Quadrata.

| Checked | Result |
|---|---|
| Files in the sandbox | present, readable, byte-identical to the repository (SHA-256 compared), first bytes `00 01 00 00` |
| Format | all 12 are sfnt `0x00010000` with `cmap`, `glyf`, `loca`, `head`, `hhea`, `hmtx`, `maxp`, `name` and every table inside the file |
| Path, case, slashes, extension case | no effect: exact, lower-case, `/`, `.TTF` and a file that does not exist all measure **identically** (595.12 px for the probe sentence at size 20, Friz Quadrata's width) |
| Game fonts as a control | `Fonts\\ARIALN.TTF` 460.28 px and `Fonts\\FRIZQT___CYR.TTF` 570.24 px differ, so the measuring path works and sees different fonts; `ARIALN` resolves in lower case and with `/` too |
| Mists-only game fonts | `MORPHEUS`, `SKURRI` fall back to Friz: they are gated behind upstream's `client-mists` feature, which the Forever build lacks |

**Root cause (source, upstream `v0.1.37`, `src/render/font.rs`):** `WowFontSystem` builds a fixed map from a table of game
font files (read from the game's CASC data) to `fontdb` families. `family_name` normalises the requested path (upper case,
`/` to `\\`), looks it up, and **falls back to Friz Quadrata when it is not there**. Nothing reads an addon font file or
calls `load_font_data` for one, and `SetFont` does not report the miss. `master` has the same function. The binary has no
option for it: its `WOW_SIM_*` names cover CASC, addon and WTF paths, not fonts. The source matches the binary by behaviour (all
five predictions from it held, listed above) and by the crates named in its strings (`cosmic-text`, `fontdb`, a `WowFontSystem`);
the binary itself cannot be diffed against the source here.

**What it affects.** Of the 133 text regions with a font in the settings window's tree (counted in the last interaction run), 130 use game fonts and are right; 3 use Cinzel (the "TwichUI"
header, the page title, a hidden title). From the font file's own advance widths (no kerning, so an estimate): "TwichUI" at
20 is about 90 px in Cinzel against the 74 px the simulator measured, and "Notifications" at 17 about 132 px against 101.
Anything that wraps, truncates or aligns around those strings, and any page using the other 11 fonts, is not validated here.
The old note that the title "shows lowercase letters Cinzel does not have" was not verified (every glyph for those strings
is in the font) and is withdrawn.

**Not done, and why.** No similar game font is substituted: it would look plausible and be wrong. The two ways to fix it are
a change to the simulator's `font.rs` (resolve `Interface\\AddOns\\<addon>\\…` against the addon roots, `load_font_data`, register
an alias), built from source with a Rust toolchain and the project's dependencies (a substantial download and build), or asking
upstream. Both wait for approval; the original binary stays as it is.

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
- **Addon fonts are not loaded, so text in them is not what the game would draw or measure.** Root cause and numbers in
  "Fonts" below. Screenshots are structural.
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

## Baseline, closeout and font pass, 2026-10-30

Run against the final files. No production code changed.

| Command | Exit | Result |
|---|---|---|
| `bash -n` on every runner; `python3 -I` parse of the four Python scripts | 0 | syntax only; `shellcheck` still not installed |
| `tools/simlab/smoke.sh` | 0 | `PASS (initialization and construction only)`: 49 of 49 pages, no Lua error |
| `tools/simlab/interact.sh` | 0 | `PASS WITH KNOWN SIMULATOR LIMITATIONS`: 74 checks, 12.1 s, started solo with `WOW_SIM_NO_PARTY=1`, only the classified voice error in the log, replay identical, wrong-on-purpose run failed on exactly its check |
| `tools/simlab/diagnose.sh` | 0 | `PASS WITH KNOWN SIMULATOR LIMITATIONS`: contract 22, baseline 3, solo 10, grouped 19, login 20 checks; login hello reached only by the synthetic event; permit-set control and four classifier controls pass |
| stale-rule control (voice errors stripped from a copy of the baseline log) | 1 | `REVIEW NEEDED`, "nothing else failed" |
| `SIMLAB_SHIM=0 tools/simlab/interact.sh` (negative control) | 1 | FAIL on the unclassified AceComm load error, as before |
| `tests/run.sh` | 0 | 141 passed, 0 failed |

Screenshots looked at: `interact-…/after.png` and `before.png` (the settings page, structural: values, rows and the greyed
state as the checks say; header and titles in Friz Quadrata), and `font-probe/probe.png` (16 lines in different font paths:
the game's `ARIALN` and `FRIZQT___CYR` rows differ, every addon-font row is Friz Quadrata). None is evidence of how the page
looks in the game.

## Baseline, cleanup-safety closeout, 2026-10-30

Run against the final files after the lab check was added to `lib.sh`, `setup.sh` and `sim.sh`.

| Command | Exit | Result |
|---|---|---|
| `bash -n` on every runner and `tests/lab_guard.sh`; `python3 -I` parse of the Python scripts | 0 | syntax only; `shellcheck` still not installed |
| `bash tools/simlab/tests/lab_guard.sh` | 0 | 28 passed, 0 failed |
| `zsh tools/simlab/smoke.sh` | 127 | refused before creating anything |
| `tools/simlab/smoke.sh` | 0 | `PASS (initialization and construction only)`: 49 of 49 pages constructed |
| `tools/simlab/interact.sh` | 0 | `PASS WITH KNOWN SIMULATOR LIMITATIONS` |
| `tools/simlab/diagnose.sh` | 0 | `PASS WITH KNOWN SIMULATOR LIMITATIONS` |
| `tests/run.sh` | 0 | 141 passed, 0 failed |

## Remaining blockers

- **In-game, still required:** that the page's controls can be reached and used by pointer and keyboard; that the
  saved values survive a reload; how the page and its previews look in the real client's fonts; everything under
  "Not covered" above. Nothing in this lab replaces those.
- **Two APIs are shimmed** (`C_ChatInfo.RegisterAddonMessagePrefix`, `IsAddonMessagePrefixRegistered`). Filing them
  upstream is not done (it is outward-facing and needs your approval).
- **Addon fonts are not loaded by v0.1.37** (root cause in "Fonts"): the settings window's 3 Cinzel strings are measured and
  drawn in Friz Quadrata, about 20 to 30% narrower than Cinzel would be. Fixing it needs a simulator change, which is not done.
- **Two delayed errors are classified, not fixed** ("Delayed failures"). The voice-settings one is the simulator's and
  Blizzard's timer; the group hello's refusal is the simulator's string rule, and whether the game would accept the same
  bytes is **unverified**; the proposed one-call probe (claim 1 of 4 there) is waiting for approval. A scenario can run the clock over a window, but
  only with those two rules permitted; any third error fails the run.
- **The 6 s login hello is reached only by a synthetic event** in the simulator's default startup ("Delayed failures"). A real
  login in a group, and the game's event order, are not tested.
- **Only one page's controls are exercised.** Reload persistence, the swatches, previews and other pages' controls are not.
- **UI source and client differ** (70532 against 70707), and the simulator patches Blizzard's UI as it starts.

## Moving to a newer simulator

Change `TAG`, `PACKAGE_SHA256`, `UI_REVISION` and `UI_VERSION` in `setup.sh` and the release name in `sim.sh`, then run
`SIMLAB_SHIM=0 tools/simlab/smoke.sh`. If the simulator has gained the two functions, the shim's `assert` says so; delete it.

## Remove it

```sh
rm -rf ../wow-ui-sim-lab   # (check the path first) everything the lab made, including its copies of Blizzard's art
rm -rf tools/simlab docs/simulator-lab.md
```

The first line does not touch the repository, the game or `wow-ui-source`. Nothing in the addons refers to the lab.
