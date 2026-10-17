# Status and support information (Troubleshooting page)

A compact status view and a short, privacy-conscious report to paste into an issue. Code: `diag/Status.lua` (collection
and report, core addon), `diag/SupportWindow.lua` (the read-only copy window, core addon), the status rows in
`TwichUI_Settings/pages/Troubleshooting.lua`. `/tui diagnostics` (the fuller report, tracing) is separate and unchanged.

It is a snapshot: a state says what the game and each addon report, never that a feature works. Nothing in it changes a
setting, turns an addon on, loads one or calls an addon's loader.

## When it is read
When the page opens (`onShow` in `Kit.lua`'s page definition), on **Refresh**, when the report is requested, and again
after a profile or switch change while the page is shown. Never in the background; no `OnUpdate`, no timer. The page's
copy is dropped when the settings close (`R.OnSettingsClosed`); the support window holds its text only while open.

## Where each answer comes from
| Shown | Source |
|---|---|
| TwichUI version | addon list metadata (`GetAddOnMetadata`), accepted only if made of letters, digits and `. - + _` |
| Release channel | `alpha` / `beta` only when the version has the suffix `tools/release.py` writes into those builds; otherwise **Unknown** (a plain `1.0.0` is a stable release *and* what an unpackaged copy shows) |
| Game client, interface, locale | `GetBuildInfo`, `GetLocale` |
| Core | `R.Life.Snapshot()` (saved data, configuration ready, start-up steps failed) |
| Settings window | `R.SettingsLauncher.Snapshot()` and the addon list; "loaded" means loaded this session, not at start-up |
| Reload needed | `R.Switches.PendingReloads()` (the switches `ReloadPending` waits on) |
| Work held back | `R.Life` counts since the game started: counts, not "pending now" (no central pending-work tracking exists) |
| Capabilities | each adapter's own answer (below) |

## Capability states
`available`, `not-installed`, `disabled` (turned off in the AddOns list), `not-loaded` (installed, not loaded),
`not-initialized` (loaded, waiting for something), `unavailable` (the call or module TwichUI needs is not there),
`off` (TwichUI's own switch), `not-applicable` (this character or configuration), `unknown`. A line uses the warning color
only when it is *wanted* (a switch or mode the player chose) and unavailable in a way they can act on.

| Capability | Adapter read |
|---|---|
| EllesmereUI: skin toolkit | `R.S`, `R.euiRegistered` (`Core.lua`) |
| EllesmereUI: border textures | `R.Borders.Ellesmere()` |
| EllesmereUI: color picker | `R.SettingsWidgets.ColorPicker.Status()` (reads only; `ready`, `on-demand`, `load-failed`, `unsupported`) |
| EllesmereUI: bag junk marking | `R.EllesmereJunk.Status()`; applies only to a Mage whose Mage selling mode is "mark as junk with EllesmereUI" |
| EllesmereUI: Unlock Mode (Food and Drink) | `R.FoodDrink.Unlock.Status()` |
| RestedXP: guide window skin, timer bars, guide waypoint | `R.RestedXPSkin.Status()`, `.Timers.Status()`, `R.QoLGuideWaypoint.Status()` |
| RestedXP: data bar guide toggle | `R.RestedXPBroker.Available()` and LibDataBroker |
| SpeakStone skin | `R.SpeakStoneSkin.Status()` |
| Skins for Auctionator, What's Training?, Forever Dungeon Journal, Attune | switch, the addon's presence, `R.S` |
| Data bar library | `LibStub:GetLibrary("LibDataBroker-1.1", true)` |

Not covered (no adapter status to read): LibAHTab (Auction House tab), EllesmereUI Bags' upgrade-mark painter, Leatrix Plus,
the other data bar entries' individual state.

## The support report (allowlist)
Included: TwichUI version and channel (or "unknown"); client version, build, interface, locale; TwichUI's interface; core
state and counts; settings-window addon state, version, load attempts, last failure code; reload-needed names; held-back
codes with counts; each addon's presence and version (version-shaped values only) and each capability's state with its
short code; each feature as on / off / not applicable by readable name (the list is `S.FEATURES`); Mage selling's handling
mode.

Left out by construction (no field reads them): character, account, realm, guild, friend and BattleTag names; chat; Journey
Chronicle entries; inventory; saved variables, backups, recovery snapshots and share payloads; file paths; credentials;
text the player typed; other addons. There is no timestamp, so the same state gives the same text.

The game gives an addon no clipboard. **Copy support information** opens a window with the exact text, selected, and says
to press Ctrl+C; it never claims to have copied anything.
