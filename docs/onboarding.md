# First-install setup (onboarding)

On a new installation TwichUI offers its layout setup (`TwichUI_LayoutWizard`, `docs/layouts/wizard.md`) as the one
setup window. It replaced the old automatic welcome dialog, which now opens only when asked (`/tui about`, Home > Welcome).
This document is the current policy. Nothing in it has been run on WoW: Forever: every behaviour is offline-tested only
(`tests/test_onboarding.lua`), and the in-game checks are at the end.

| Part | File | Loaded |
|---|---|---|
| The record's shape, its migration and repair | `!!!TwichUI/Persist.lua` (`NormalizeOnboarding`) | always (core) |
| The policy: when to open, holding EllesmereUI's first run, Do this later, Skip, handing back | `!!!TwichUI/Onboarding.lua` | always (core); reads one field at login once setup is finished |
| The partner-installer registration, the check after a reload | `!!!TwichUI/LayoutsLauncher.lua` (`L.RegisterInstaller`, `L.Continued`) | always (core) |
| First-run copy, Skip setup, EllesmereUI's own setup, Do this later, the dimming | `TwichUI_LayoutWizard/Pages.lua`, `Window.lua`, `Model.lua` | on demand, only when the setup opens |
| Planning while EllesmereUI's first run is held for TwichUI | `TwichUI_Layouts/AdapterEllesmere.lua` (`A.HeldForUs`) | on demand |

## The record

`TwichUIDB.onboarding = { v = 1, state, offers, why, held }`. Account-wide, like the rest of `TwichUIDB`, and like
EllesmereUI's active profile, which the setup changes for every character. A record, not a setting: never in a profile,
a backup, a restore or a share (`TwichConfig.LOCAL`, `RS.OWN_LEFT_OUT`); protected in the saved-data explorer.

| State | Means | Opens by itself |
|---|---|---|
| `new` | a new installation; the setup has not been opened | at the first clear moment of any session (login or reload) |
| `started` | opened, never answered (a reload or disconnect with it open) | at a real login only, while `offers` < 3 |
| `deferred` | put off: Do this later, the close box, Escape | at a real login only, while `offers` < 3 |
| `installing` | an install made from it waits for its reload, its check, or a recovery (`partial`, `mismatch`, `interrupted`, a restore under way) | on its result, at a login or reload, while `offers` < 3 |
| `done` | the install checked out (`verified`), or the player kept it after the check (`kept`), or a layout is managed (`managed`) | never |
| `skipped` | Skip setup (`user`), EllesmereUI's own setup instead (`native`), or the install was restored (`restored`) | never |
| `existing` | an installation from before onboarding | never |

- **Opening is not completion.** Opening moves `new` to `started`. `done` is reached only from the layout records:
  `TwichUIDB.layouts.install.state == "verified"`, or no install record and a management record (the player chose Keep this
  setup, possibly after a mismatch). `O.Sync` reads those two records raw (TwichUI_Layouts need not be loaded) and never
  writes them; the rollback journal's lifetime is unchanged.
- `offers` counts automatic openings in the current phase; it starts again at 0 when an install begins (`installing`).
  Opening by hand never counts. After three automatic offers the setup opens only when asked, and the deferral line says so.
- `why` is a short code for the last change (`fresh`, `opened`, `later`, `closed`, `applied`, `verified`, `kept`,
  `managed`, `user`, `native`, `restored`, `reset`, `migrated*`, `repaired`).
- `held`: TwichUI held EllesmereUI's own first-run picker for this setup in some session, and EllesmereUI's setup has not
  run since. While it is set and the setup is still first-run, the first page offers **Use EllesmereUI's setup instead**.

### Older installations (migration, once, in `Persist.Normalize`)

| What the saved data holds | Becomes | Why |
|---|---|---|
| nothing at all (no settings, no other TwichUI saved variable) | `new` (`fresh`) | a new installation, by the rule the welcome marker always used |
| a managed layout install with no unfinished record | `done` (`migrated-managed`) | completed wizard records are recognized |
| any other layout record | `existing` (`migrated-layout`) | its result is where it always was (Home / Troubleshooting > Layout setup) |
| the old welcome marker still `pending`, nothing installed | `new` (`migrated-new`) | a new installation that never got the old dialog |
| anything else (the welcome `seen`, or no marker) | `existing` (`migrated`) | "welcome seen" proves an existing user, not a layout set up |
| an unreadable record | `existing` (`repaired`, counted as `onboarding-repaired`, not a loss) | never a fresh offer |
| a record with `v` above 1 | left exactly as it is; nothing opens; reset refuses | a newer TwichUI's |

A missing record on an existing save never means "new": an existing user is never pushed into an automatic installer
because the field is absent. An addon update changes nothing (the version is never read). A new character on an account
whose setup is done or skipped gets nothing automatic (the EllesmereUI part already covers every character; the TwichUI part
is the install's profile, which another character can pick in Profiles, or the setup can be run for it by hand).

**For testing:** `/tui layout firstrun` prints the state; `/tui layout firstrun reset` sets it back to `new` (refused in
combat and over a newer record). Nothing else is touched: no install record, management record, profile or EllesmereUI
setting. It takes effect at the next login or reload. With an install already recorded, the setup then opens on its result.

## Opening by itself

`Onboarding.lua` listens for `PLAYER_ENTERING_WORLD`, `PLAYER_LEAVING_WORLD` and `PLAYER_REGEN_ENABLED` only while an
automatic offer could still happen this session (none for `done`, `skipped`, `existing`, or once offered or answered).
The first world entry of the session says login or reload (`isInitialLogin`, the event's first payload value; checked in
`Blizzard_APIDocumentationGenerated/SystemDocumentation.lua`). 4 seconds after it, then every 2 seconds up to 15 times per
world entry, and again after combat, it looks whether anything is in the way (`O.InTheWay`):

`settings` (configuration not ready), `world` (a loading screen), `combat`, `flight`, `interface-hidden`, `banner` (a game
toast or a cinematic), `cards` (a TwichUI card showing or waiting: it never holds one back), `layouts` (the check after a
layout reload, `LayoutsLauncher.Continue` at 3 s, has not run yet), `ellesmereui-setup` (EllesmereUI's own first run is due
and not held for TwichUI: its picker, or another installer, has the session), `ellesmereui-style` (EllesmereUI's look picker
is due: `EllesmereUIDB.styleChoicePending`, read only).

When clear it opens the setup through `LayoutsLauncher.OpenWizard` (the only time the wizard is loaded at login), once a
session. If the result after the setup's own reload is already open, that is the session's offer. A load failure is said
in chat by the launcher, counted (`onboarding-load-failed`) and, if EllesmereUI's first run was held for it, handed back
(below). Nothing polls, no `OnUpdate`, no timers are left once it opened, gave up or was answered.

## The window on a first install

The first page (`Pages.FIRST`) greets, says what the setup arranges, that you pick the layout, helpers and personal touches,
that nothing changes until you review it and press Apply, that a restore point is made first, and that EllesmereUI's part
applies to every character on the account (TwichUI's to this character). Below it: **Skip setup**, and **Use EllesmereUI's
setup instead** when that was held back for this one. The footer's **Close** reads **Do this later**. Start is "continue
setup"; the rest of the wizard is unchanged.

| The player | Outcome |
|---|---|
| Do this later, the close box, Escape, the full-size preview's Exit | `deferred`; one chat line: when it comes back (or that it won't by itself), where it is (`/tui layout`, Home > Interface layout), and that EllesmereUI's setup was held back for it if so |
| Skip setup (asks first) | `skipped` (`user`); nothing applied; EllesmereUI's held first run is handed back at once |
| Use EllesmereUI's setup instead (asks; refused in combat) | `skipped` (`native`); EllesmereUI's own picker is shown |
| Apply, then close | `installing`; never "put off" |
| A reload the player starts from the result | the result reopens after it (the launcher's resume note); `done` once checked |
| Their own `/reload` after Apply | the launcher's chat line; `done` if it checked out, else the result reopens at the next login or reload |
| A partial, mismatched or interrupted install | the setup opens on its result (Restore, Reload now, Check again), never on the layout choice |
| Restore that checks out | `skipped` (`restored`) |
| Combat while it is open | the window stays (the wizard's policy: Apply, Restore and reloads are refused in combat); the dimming lifts and returns after |

The setup is never undismissable: the dimming takes no input, Escape and the close box always work, and every way out has
a defined outcome.

## EllesmereUI's own first run

Evidence: `reference_addons/EllesmereUI` 9.6.8 (`## Version` in its `.toc`). Not claimed for other versions; every call
is presence-checked.

| Dialog | When EllesmereUI shows it | Supported way to coordinate | What TwichUI does |
|---|---|---|---|
| **Module picker** (`EllesmereUI_FirstInstall.lua`) | its first session only: at its `ADDON_LOADED` `ComputeShowOnLogin` (534) decides, sets `EllesmereUI._firstInstallPending = true` (575) and, on Forever, `styleChoicePending`; at `PLAYER_LOGIN` + 0.5 s it shows unless `_externalInstaller` is set (586) | `EllesmereUI.RegisterExternalInstaller(name)` (`EllesmereUI_Profiles.lua` 5080): "A partner installer that owns the whole first-run experience calls this ... the picker's reload-handshake flag still arms ... until the installer's import completes" | registers at `PLAYER_LOGIN` (before the 0.5 s timer) when the record is `new`, `_firstInstallPending` is up, the setup's two addons exist and are on, and no other installer registered |
| **Look picker** (`EllesmereUI_StyleChoicePopup.lua`) | at a `PLAYER_LOGIN` where `styleChoicePending` is set and `_firstInstallPending` is not (217); a registered installer makes it `Stamp()` the choice as answered for good (219) | the same registration, but it is permanent | **never registers in such a session.** In EllesmereUI's first session it returns at 217 before reading the registration, so holding the module picker never stamps it. In a later session it shows by itself; the setup waits for it (`ellesmereui-style`). Every way out of it stamps (`KeepLook` 132, Escape 108, a pick) |
| Other first-login popups (group finder, video guides, launch, kick tracker, window skins, patch notes, CDM's Edit Mode reload) | they treat a Forever client or `_firstInstallPending` as a new install and stay silent | none needed | nothing |

**Completion.** EllesmereUI's flags are its own; TwichUI only reads them and never writes them. A layout install imports
through `ImportProfileSilent` (4957), which calls `ImportProfile` (5040); that stamps `firstInstallPopupShown = true`,
clears `_firstInstallPending` and, on Forever, `styleChoicePending` (3666-3673). That is EllesmereUI's documented completion
for a partner installer.

**The deadlock this resolves.** The engine refused to plan while `_firstInstallPending` was up (its picker ends in its own
import and reload). With TwichUI registered, that flag is the handshake TwichUI's own import answers, so refusing would wait
forever. `A.HeldForUs(E)` (`_externalInstaller == "TwichUI"`) lifts that one refusal in the adapter's `Plan` and in the
wizard's compatibility list (an info line instead of Blocked). Another installer's registration still blocks, with the reason.

**What EllesmereUI's own comment claims and its source does not do.** The registration comment says "if the installer never
imports, the picker returns on a later login without a registration". In 9.6.8 it doesn't: the first session's module
addons create `profiles[active].addons[folder]` (`EllesmereUI_Lite.lua` `NewDB` 267-269), and at the next load
`ComputeShowOnLogin` reads that data as an upgrade, stamps `firstInstallPopupShown` and never shows the picker again. So
holding it for one session is effectively final unless TwichUI hands it back. Hence:

### Fail-open: handing EllesmereUI's first run back

`O.HandBack` calls `EllesmereUI.ShowFirstInstallPopup` (exported at `EllesmereUI_FirstInstall.lua` 517; not documented as
a partner API, so it is presence-checked and called once a session, in a `pcall`, never in combat). It seeds its boxes from
the addons' current enable state and ends in its own reload (its Escape is disabled by design, 142). It is called when:

- the player skips the setup (or picks EllesmereUI's setup) while the first run is held (`held`);
- the setup can't open in the session that holds the first run (it loaded but didn't start, or erred while opening).

If the setup's addons are missing or turned off at login, nothing is held and EllesmereUI's picker shows as usual. If the
export is missing, the line says EllesmereUI's options have its choices. The registration itself can't be undone within a
session (no unregister exists): holding lasts until the next reload either way.

| Moment | Who owns EllesmereUI's first run |
|---|---|
| Initial login, a new record, EllesmereUI's first session, the setup loadable | TwichUI (registered at `PLAYER_LOGIN`) |
| The setup open | TwichUI; planning allowed (`HeldForUs`) |
| Do this later | still TwichUI this session (the registration stands); the module picker doesn't come back by itself afterwards (above), so **Use EllesmereUI's setup instead** stays on the first page while `held` |
| Skip, EllesmereUI's setup instead, a setup that can't open | EllesmereUI: its picker is shown now |
| Apply | answered by the import (EllesmereUI stamps its own state) |
| The setup's reload | TwichUI's install record is under way, so the launcher registers at EllesmereUI's `ADDON_LOADED` (as before); no picker can show anyway |
| Verification, completion | nothing to hold; `held` cleared |
| A later login after a deferral | nobody holds: EllesmereUI's look picker (Forever) shows first, then the setup |
| An existing TwichUI user, or setup done or skipped | EllesmereUI, untouched |

## Other addons' introductions

No universal popup blocker. TwichUI never hooks `StaticPopup_Show`, never enumerates or hides frames, and never suppresses
errors, permission or security prompts, data-loss warnings, import or reload confirmations, compatibility warnings, group
invites or anything gameplay-critical. The only integration is EllesmereUI's documented partner registration, plus the
export above as a fallback. `reference_addons/` holds only the EllesmereUI suite; no other addon there has a supported
"external installer" or "skip welcome" mechanism, so other addons' introductions (RestedXP, SpeakStone, Attune, ...) may
still appear on a first login. TwichUI's own: the old welcome dialog no longer opens by itself; the Welcome Back card has
nothing to show on a new installation (no Chronicle yet); zone, training and friend cards are gameplay notices and are not
held back (the setup waits for them instead of opening over them); the saved-data notice and errors are untouched.

## The dimming

One frame, `TwichUILayoutWizardScrim`, made with the window (`Window.lua` `BuildScrim`) and reused: a warm charcoal
texture (`0.035, 0.030, 0.025`) at 40% (`W.SCRIM_ALPHA`), no vignette, glow, blur or ornament.

- **Layering:** a child of UIParent with `SetAllPoints(UIParent)` (so it follows the screen size and UI scale by itself),
  strata `HIGH` at level 0; the window is `HIGH` above it. The game's dialogs (Apply's question, StaticPopups) are `DIALOG`,
  tooltips `TOOLTIP`: above it. The HUD (`MEDIUM` and below) is dimmed, not hidden or moved; UIParent is never hidden and no
  protected frame is touched. EllesmereUI's own popups sit at `FULLSCREEN_DIALOG` (`EllesmereUI_Popups.lua` 87), above it.
- **Input:** `EnableMouse(false)` and no keyboard: clicks, camera and keys go through. The window keeps its own mouse
  handling; no global keyboard capture.
- **Motion:** fades in over `Look.Motion.TIME.window` (0.16 s) through the shared `Look.Motion` Fader; "Reduce window
  motion" (`ui.reduceSettingsMotion`) shows it at once. It never fades out: it hides the moment the window hides.
- **Lifecycle:** shown last in the window's `OnShow` (an error before it leaves the screen undimmed); hidden first in its
  `OnHide`; lifted in combat (`PLAYER_REGEN_DISABLED`) and back after; the full-size preview (`Overlay.lua`, its own 78%
  scrim) sets the window aside, which hides this one: never two; Back brings it back without a second fade; Exit removes
  both. A failed open (`LayoutsLauncher.OpenWizard`'s `pcall`) calls `Window.Abort`: dimming hidden, window hidden, session
  ended, listeners off, not counted as a deferral; a window built only part way is built again at the next open. A reload
  takes everything down; nothing is saved.

## Performance and diagnostics

- Login with setup finished: Persist's normalization of one small table, `O.Sync` (a few field reads), one `PLAYER_LOGIN`
  handler that returns at its first test. The wizard is not loaded, no event listeners stay registered.
- No new `R.Perf` scope: the work is event-rare (a handful of reads per world entry while owed) and trivially cheap; the
  costly part, loading and building the wizard, is already scoped (`layoutwizard.load`, `layoutwizard.build`). The dimming's
  frame and texture are counted in the existing `layoutwizard.frames` gauge; it registers no events of its own.
- `/tui diagnostics` > Start-up and lifecycle: the state, its `why`, the offers, whether EllesmereUI's first run is held
  (saved, and this session), whether it was offered or answered this session, what was last in the way, and this session's
  reason codes in order (bounded to 16): `hold`, `hold-missing`, `hold-disabled`, `hold-no-api`,
  `hold-other-installer`, `hold-error`, `open`, `open-already`, `load-failed`, `deferred`, `skipped`, `native`,
  `native-unavailable`, `native-error`. Lifecycle counts: `onboarding-waited`, `onboarding-load-failed`. Codes only: no
  names, places or text.

## Tests

`tests/test_onboarding.lua` (through the real core, engine and wizard; stand-in frames; a stand-in EllesmereUI with both
first-run loaders as 9.6.8 has them, `tests/layouts_mock.lua`): a new installation with EllesmereUI's first run (held, no
picker, look picker neither shown nor stamped, the setup opens once, no welcome dialog, Start and Apply not blocked, the
import answers EllesmereUI, the reload keeps it held, the result after it, `done` only then, later logins load nothing);
Do this later, Escape, the close box, a reload and a login, the bound; Skip (declined, accepted, handed back), EllesmereUI's
setup (combat refused), Skip with nothing held, no exported picker; EllesmereUI loading first, a look-picker-only session,
an existing user, the setup missing or off or broken, no partner API, another installer; every migration row, damaged,
newer, update, another character; applied and closed, the player's own reload, a clean failure, part way, restore,
interrupted; combat, flight, hidden interface, cards, the bound on looks, the late post-reload check; the dimming's
layering, input, colour, fade and reduced motion, screen change, combat, the full-size preview, eight reopenings, a failed
open; the command, reset and the report; and source scans (no global hooks, frame scans, `OnUpdate`, or writes to
EllesmereUI's flags). 22 hand mutations of the safeguards were each caught. `tests/test_welcome.lua` checks the dialog never
opens by itself.

## In-game checks (none done; WoW: Forever)

1. Fresh account (move `!!!TwichUI.lua` and `EllesmereUI.lua` out of `SavedVariables` with the game closed): one TwichUI setup
   window a few seconds after the world loads; no EllesmereUI module picker, no flash of it; no look picker; no TwichUI welcome.
2. Its first page reads right at 1080p and with larger fonts; Do this later, Skip setup, EllesmereUI's setup are reachable.
3. The dimming: readable world behind it, window and its tooltips clear, Apply's question clear and clickable; clicking the
   world, targeting, the camera and keys work through it; it follows a UI scale change and a window resize; it lifts in combat.
4. Apply, Reload now: no EllesmereUI picker during the reload; the result opens; later logins show nothing.
5. Do this later on a fresh EllesmereUI: the next login shows EllesmereUI's look picker first (Forever), then the setup.
   **Use EllesmereUI's setup instead** opens EllesmereUI's picker and its Done reloads.
6. Skip on a fresh EllesmereUI: EllesmereUI's picker appears at once, and works.
7. Rename `TwichUI_LayoutWizard` (or turn it off) on a fresh account: EllesmereUI's picker appears as normal.
8. An existing install (managed, or just the old welcome seen) updated to this build: nothing appears.
9. A second character on a set-up account: nothing appears.
10. `/tui diagnostics`: the first-install lines read right; `/tui layout firstrun reset` brings the offer back next login.
11. Other addons' first-login introductions: note which still appear (they are not suppressed).
