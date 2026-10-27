# The layout setup wizard (Phases 4 and 5)

`TwichUI_LayoutWizard/` is a load-on-demand sibling addon (`RequiredDeps: !!!TwichUI, TwichUI_Layouts`, no saved variables
of its own) that lets a recipient review compatibility, pick one of the two bundled layouts (Classic or Compact Adventure; Phase 5), look at it
to scale and then at full size over their own screen, choose a small TwichUI helper preset, adjust two personal choices, review exactly what would change, apply it with a restore point, see it
checked after the reload, and put the previous setup back. It adds no engine of its own: everything that changes the game
is `TwichUI_Layouts`' pipeline (Phase 2), fed by Phase 3's package and resolved screen geometry. Nothing here has been
run on WoW: Forever (`implementation-status.md`, "In-game checks").

## Opening it, and what loads when

| Entry | What it does |
|---|---|
| `/tui layout` (hidden command, like `/tui bars` and `/tui nav`: listed on the pages that use it) | `LayoutsLauncher.lua` `L.Command`: bare, `wizard`, `setup` or `open` open the wizard; any other word goes to the developer commands in `TwichUI_Layouts/Dev.lua` (`/tui layout help` lists them) |
| Settings > Home > **Interface layout** > Layout setup | closes the settings window and calls `L.OpenWizard()` |
| Settings > Troubleshooting > **Layout setup** > Open | the same; with an install recorded it opens on the result (and Restore) |
| After a reload the player started from the wizard | `L.Continue` (the check after login) opens it once on the result; see "Reload and resume" |

Not offered, deliberately: a Welcome-dialog button (the dialog's wrapped button row and its tests are a different
feature's, and the wizard is reachable from Home), a permanent minimap or broker button (nothing in the wizard's source
mentions a minimap or a broker; the test scans for it), and any first-run or login prompt. A new installation, a login
with a stale note and a login with nothing waiting all load and open nothing (`test_layout_wizard.lua` §2).

Loading: `L.LoadWizard()` loads `TwichUI_LayoutWizard`, and the game loads `TwichUI_Layouts` first (its dependency). A
missing folder, a disabled addon, a missing dependency and an addon that loaded but never said it was ready are each said
in chat in plain words (`L.ExplainWizard`), kept for `/tui diagnostics` (`L.Snapshot().wizardFailed`), and leave the core
untouched. The window is built the first time it opens and kept; its pages are built when first shown; closing hides it.

## The workflow

Six steps, one window (780 × 590, TwichUI's own look, `Look.Shell`; fitted to small screens by `R.FitToScreen`; closes
with Escape through `UISpecialFrames`, never `RegisterGameMenuEscHandler`). A stepper at the top reaches only steps already
reached with Next; the footer holds Close, Back, and Next (Start on the first step, Apply on the review). The footer's
note says why a button is disabled.

| # | Step | Shows | Changes |
|---|---|---|---|
| 1 | Welcome | the emblem, what the setup does, and **Does it work here?**: EllesmereUI (present, usable, version, tested-with, Forever build, its own first-run setup pending), TwichUI profiles, the screen (size, and whether the layout fits at standard size, with the overlaps), whether this is a preview build, combat, and an install already recorded (with a link to its result). Each line has a word (Ready, Check, Blocked, Note), not a colour alone. | nothing |
| 2 | Layout | a card for each layout, Classic and Compact Adventure (its picture, what it says, a Preview-build tag; the selected one unfolds what it covers), the preview, its scenario selector and the full-size button. Choosing a card re-draws the preview at once. | the layout choice is remembered |
| 3 | Helpers | the **TwichUI helpers** choice as three cards and the preview | the pick is remembered |
| 4 | Personalize | accent colour swatches (with the chosen one named), the size cards (Standard, Larger), Start over, and the preview, which follows each pick at once | the picks are remembered |
| 5 | Review | the plan: your choices; TwichUI (at once, this character only): the profile copied and switched to, how many settings are set, what is turned on, how many on-screen pieces are placed; EllesmereUI (after a reload you start, every character on the account): the profile made and made active (and, on a repeat, that changes made in it since are replaced), what is replaced, positions and text sizes; **Left alone**; **Not placed** (the objectives, which Blizzard's Edit Mode places); what doesn't fit; blockers with their reasons; what happens if a step fails. Apply is in the footer. | nothing until Apply is confirmed |
| 6 | Result | what the install record says now, with the actions that make sense: waiting for a reload (Reload now, Restore), checked after the reload (Restore, Keep this setup, Check again, Set up again), not everything reads back (the differences; Restore, Check again), only partly applied (what was done and what failed; Restore, Reload now), interrupted (Restore), restore waiting for a reload, restore not fully checked, restored, nothing changed (a clean failure, with its reason), a damaged, newer or other-character record (said, with only what is safe offered) | only through its confirmed buttons |

### What never happens by itself

`Model.lua` is the whole of the wizard's behaviour, with no frames, so it is tested without a screen:

- Choosing remembers a pick (`TwichUIDB.layouts.wizard`) and re-draws the preview. It touches no profile, no EllesmereUI
  data and no feature (`test_layout_wizard.lua` §5 and §11 snapshot the game's saved data before and after, and count
  calls to `LY.Apply`, `LY.Restore`, `LY.Detach`, `ReloadUI` and EllesmereUI's import, switch and delete: all zero).
- The full plan (`LY.Plan`, read only) is computed only when the review is shown, again only when a pick or the screen
  changed, and dropped when the player leaves the review or closes the window (it holds the payload it would import:
  about 2 MB on the offline measurement).
- **Apply** is bound to the plan key the confirmation described: `Model.Apply(key)` refuses a different key ("stale"), the
  confirmation's `valid` check refuses it before that, and `LY.Apply` refuses it a third time. A screen that changes while
  the question is open cannot turn into a different install than the one approved.
- Apply, Restore, Keep this setup, Forget the record and Reload each sit behind a confirmation that names the exact scope
  (`R.Interact.Confirm`) and are refused in combat by the model, the confirmation (`combat = true`) and the engine.
- Nothing reloads by itself. **Reload now** is a button; it leaves a note (below) and calls `ReloadUI()`.

### Reload and resume

When the player presses **Reload now**, the wizard writes `layouts.wizard.resume = "install"` (or `"restore"` if the
record says a restore is waiting) just before `ReloadUI()`. At the next login `LayoutsLauncher.Continue` (3 seconds after
`PLAYER_LOGIN`, only while the install record says `applying`, `applied` or `restoring`) checks the install through the
engine as before and prints its chat line; **then, only if that note is set, it opens the wizard on the result** and the
wizard uses the note up. A reload the player made themselves gets the chat line only, and the wizard stays closed until it
is asked for. A leftover note with nothing waiting opens nothing. Verification itself is `LY.Continue`: read only.

## Choices

The package (`Classic.lua`, format 3) declares its `choices`; the schema is in `architecture.md` §13. Each choice names
exactly what it writes, and `Package.lua` refuses anything else. The wizard shows nothing the package doesn't declare.

| Choice | Kind | Options (default first) | Writes | Verified after the reload by |
|---|---|---|---|---|
| `helpers`: TwichUI helpers | preset (layer "preset") | **Leave them as they are** (nothing); **On-screen helpers** (`modules.classBars`, `modules.markersBar`, `modules.foodDrink` on); **Helpers and navigation** (the same, and `modules.navigation`) | TwichUI switches, turned on only (a preset naming a switch off, a non-switch or an EllesmereUI setting is refused) | the TwichUI adapter's fingerprints |
| `accent`: Accent colour | enum (layer "choices"), `sets = { "ellesmereui:root.euiAccent" }` | **Aged gold** (the layout's own, `r .788 g .635 b .290`), **Your class colour** (`useClass = true`), **Verdigris** (`.36 .58 .57`, TwichUI's own teal), **Ember** (`.80 .45 .30`), **Dusk blue** (`.47 .60 .80`) | EllesmereUI's profile-root `euiAccent` and nothing else of its look (`EllesmereUI_Profiles.lua:3464`: `merged.euiAccent = DeepCopy(imported.euiAccent)`; `EllesmereUI_UICore.lua:527` `SetActiveProfileAccent` shows the shape `{ custom = { r, g, b }, useClass }`) | **by value**: `accent:class` or `accent:rgb:r,g,b` to three places (EllesmereUI's serializer keeps 14 digits, so an exact fingerprint of the floats would not match after the round trip) |
| `size`: Size | density | **Standard**, **Larger** | the geometry's density: component sizes (chat, damage meter, minimap, objectives) and the registered text sizes (chat text and tabs, meter text and bar height) | the placed positions and text sizes (Phase 3's checks) |

The three feature switches in the preset are the author-proposed set (D21 below): quiet, local, on-screen pieces that the
layout already has a place for (`class-bars`, `marker-bar`, `food-drink`, `nav-arrow`). None of them is a key in
`TwichConfig.LOCAL`: nothing that shares, accepts setups, plays a sound, acts for you or talks to other players is ever in
a preset (`test_layout_wizard.lua` §5 checks each key against `LOCAL`).

**Not offered: cursor-following or fixed tooltip.** It is one of the three personal choices that were asked for, and it
has no adapter that can honestly back it today:

- Whether a tooltip follows the cursor is `EllesmereUIDB.tooltipAnchorCursor`, a **root key of the account-wide saved
  variable**, not a profile field (`EUI_BlizzardSkin_TooltipAnchor.lua:125, 148, 463`). It is one of the "Window & Tooltip
  Skins" account globals (`EllesmereUI_Profiles.lua:2043` `BLIZZ_SKIN_GLOBAL_KEYS`).
- The only supported way to write it is `ImportProfile`'s `blizzSkinGlobals` bundle (`:3326`), and
  `EllesmereUI.ApplyBlizzSkinGlobals` (`:2157`) sets **every** key of that bundle, "INCLUDING nil", from the payload: a
  one-key choice would reset the recipient's whole window-and-tooltip skin to defaults, for every character, and Restore
  (`SwitchProfile` + `DeleteProfile`) would not put it back. That is the whole-`EllesmereUIDB` restore point Phase 2
  deferred (D3, D5), which has not been built.
- The fixed position (`tooltipFixedPos`) is per profile but is not among the root keys the import takes (`ROOT` in
  `AdapterEllesmere.lua`), so a layout could not place it either.
- TwichUI has no tooltip-anchor setting of its own.

So the wizard shows two personal choices (accent, size) and says nothing about the third. Offering it needs D3 (a restore
point for account-wide EllesmereUI units) and D5 (window and tooltip skins as a managed unit); until then it stays out.

## Saved state

`TwichUIDB.layouts.wizard = { v = 1, variant = "<layout id>", picks = { [choice id] = option id }, resume = "install" | "restore" }`, beside the
install record (`layouts.install`, `Journal.lua`), covered by the same `layouts` entries in `TwichConfig.LOCAL` and
`RS.OWN_LEFT_OUT` (records, not settings: a backup or a share never carries them). Read-only reading, narrow repair
(`State.lua`):

- not a table, or `v` not a whole number ≥ 1: defaults; nothing is written by reading;
- `v` newer than this version: defaults are used and **a pick never overwrites it** (`test_layout_wizard.lua` §9);
- a pick that isn't an option of its choice goes back to that choice's default and the others are kept; unknown choices
  and a bad `resume` are ignored; a `variant` that isn't one of the package's goes back to the first (Classic); a record
  with no `variant` (from Phase 4) reads as Classic; the next save writes a clean record. Every writer (a pick, the layout
  choice, the reload note, using the note up) saves the chosen layout with the picks, so none forgets it;
- bounded: one layout id and at most one entry per choice the package declares (3). The scenario and the open state of the
  full-size preview are never saved.

## How it uses the pipeline

| Phase 2 stage | In the wizard |
|---|---|
| Validate | `LY.Plan` validates the package, including its choices (the wizard does not validate on its own) |
| Resolve | the picks go to `LY.Resolve` as `opts.picks`; the geometry for the preview is `LY.Geometry.Resolve` for the same screen and density |
| Review | `LY.Plan` → `Model.Review()` (text only) |
| Snapshot, Apply | `LY.Apply(pkg, variant, key, { picks })`: the snapshot is taken and checked before the record is written; the record keeps the picks |
| Verify | after the reload (`LY.Continue`), or `LY.Verify(false)` from Check again (read only; nothing is repaired) |
| Restore | `LY.PlanRestore` → the confirmation → `LY.Restore(key)` → after the reload `LY.VerifyRestore` |
| Detach | "Keep this setup" and "Forget the record": `LY.Detach` after a confirmation |

Engine changes this needed (all in `TwichUI_Layouts`, `architecture.md` §13): package format 3 with `choices`;
`LY.Resolve` `opts.picks` and `resolved.picks`; the picks in the plan key and in the install record (validated, at most 8);
the EllesmereUI adapter's acceptance of `root.euiAccent` (and only that) from a choice, and its by-value check.

## The preview, the scenarios and the full-size overlay

One **scene** (`Scene.lua`, no frames) feeds both drawings, so the miniature, the overlay and the install cannot disagree:

- the **components** are `LY.Geometry.Resolve`'s result for the chosen layout (`opts.variant`), this screen and the picked size:
  the same call `LY.Plan` makes, so the plan, the miniature and the overlay hold the same rects (`test_layout_wizard.lua` §15
  compares them for four screens, both layouts and both sizes);
- the **pieces inside them** (unit frames, cast bars, the action bars, the party frames, TwichUI's own markers) are
  `LY.Elements` for that geometry: the install's own position math (`EllesmereAdapter.Resolved`, `TwichUIAdapter.PlaceOne`)
  applied to the same stored records. §15 compares every EllesmereUI piece with what the install then **writes** into the
  profile, using a centre-from-record formula written out independently in the test;
- what is drawn **inside a component** (chat lines, meter bars, objectives text) and the tooltip is sample content, chosen by
  the scenario; plain sample text, nothing from the player's game.

Nothing is a hand-coded coordinate of the layout: the only fractions in the code are the miniature's sample shapes inside a
chat, meter, minimap or objectives box.

**Scenarios** (Solo, Target selected, Dungeon party, Long objectives, Tooltip visible) change only what the sample shows, never
where anything is (a test compares every component's rect across all five). Solo: your frame, pet and bars. Target: adds the
target, its target, its cast bar and yours. Party: the party frames (five members in a column, or a row with `partyHorizontal`,
the arrangement being a sample), the focus frame and its cast bar, five meter rows, six chat lines. Long objectives: two long
quests that wrap, drawn at the box's width; if they need more height than the box has, the overlay says "The text runs past this
box" instead of hiding it. Tooltip: a sample tooltip at `GameTooltipDefaultContainer`'s first point, read the way Blizzard's
`GameTooltip_SetDefaultAnchor` reads it (only when it is placed against the screen), else Forever's own default (bottom right,
9 in, 85 up); EllesmereUI can move or follow-the-cursor tooltips, which the preview does not show. A scenario is not remembered.

**The miniature** (`Preview.lua`) draws the scene to scale on a frame with the viewport's proportions (330 × 200 at most): each
managed component a box with sample shapes, each piece a flat rectangle, accent outlines, overlapping or off-screen components
outlined in the warning colour with "!". Boxes and pieces are made once and moved on every draw. Under it: the scenario tabs and
**See it full size**.

**The full-size overlay** (`Overlay.lua`) draws the same scene at the real size and place, in UIParent's own units from the centre of
the screen, with sample content (unit frames with health and power, action bars as button squares, cast bars, party blocks,
chat lines, meter bars, objectives text, a tooltip, TwichUI's pieces as labelled markers). What it is and is not:

| | |
|---|---|
| Preview, and says so | a bar of controls with "PREVIEW  <layout> - nothing is applied", the sentence that your interface is dimmed behind it and not hidden or moved, "(sample)" on every box, "Doesn't fit this screen: …" when it doesn't |
| Click-through | the covering frame and every box take no mouse and no keyboard; only the control bar does (a test walks the frame tree) |
| Inert | no secure template, no `SetAttribute`, no action or spell call, no hook, no timer, no `OnUpdate`, no `ReloadUI`, no `LY.Apply`/`Restore` and no saved variable named in `Overlay.lua` (the source is scanned); the mock buttons are textures |
| No writes | opening, switching layout, changing scenario and closing change no profile and call no install; the only thing remembered is the layout choice, as in the wizard |
| Out of combat | it will not open in combat (the button says why) and closes when combat starts |
| The live interface | **not hidden or moved**: hiding UIParent would hide the preview with it, and moving or hiding protected frames is not allowed, so the screen behind is dimmed (an opaque-ish scrim) instead. EllesmereUI's real bars, frames and chat stay visible behind it. If the dimming is not enough on someone's screen, the answer is the miniature, not forcing the live UI away |
| Controls | **Back** (the wizard where it was left), **Switch to <other layout>** (shows the other layout at once; nothing applied), **Exit** (closes the preview and the wizard, nothing changed), the five scenario tabs, Escape (the game's own list, once: closes the preview and returns to the wizard) |
| Cleanup | it listens for `PLAYER_REGEN_DISABLED` (closes), `DISPLAY_SIZE_CHANGED` and `UI_SCALE_CHANGED` (re-draws for the new screen) only while shown; it closes when the wizard closes, when combat starts and when a profile changes (`Profiles.OnChange`, one listener added once for the session); asking for the wizard again (`/tui layout`) brings the setup back |

The wizard window is **set aside, not closed**, while the preview is up (`Window.Suspend` / `Resume`): the session, its step and
its picks stay, and closing the window while it is set aside ends the session as closing always does.

**Fidelity limits** (what the preview does not claim): EllesmereUI draws the real frames, snaps them to its pixel grid and can
differ by a few units from a sample size; third-party styling (borders, textures, fonts, colours) is not reproduced, only
illustrated; a piece whose size the layout's data doesn't give (the Cooldown Manager's bars, class power, the data bars, the
raid frames, the minimap's shape) is not drawn at all; TwichUI's own pieces are 26-unit markers because their size belongs to
their features; the pet and stance pieces sit outside Compact's checked box (they follow it and are drawn, but an overlap
with chat there is not diagnosed); the quest tracker is placed by Blizzard's Edit Mode and is shown but not applied; the
default tooltip position is the game's, not EllesmereUI's. Offline: the geometry takes about 0.12 ms and a miniature draw
about 0.14 ms on stand-in frames (the client's `SetPoint` and `SetSize` cost more; not measured).

## Artwork

Four sources existed in `../assets/` (names are the author's: `wizard_suite_emblem.png`, `wizard_classic_adventure.png`,
`wizard_personalize_screenfit.png`, `wizard_compact_adventure.png`). Their contents and geometry were read from the files,
not assumed, by `tools/make_layout_wizard_art.py` (standard library only, like the other `tools/make_*.py`; `--check`
builds nothing and prints the findings). Copies are kept in `assets/layout-wizard-*-source.png` (not packaged).

| Source | Found | Runtime file | How it was made |
|---|---|---|---|
| Setup emblem | 1254 × 1254, 8-bit **RGB, no alpha**: the transparency is a grey checkerboard painted into the pixels | `media/emblem.tga`, 128 × 128 | Background removed by flooding from the border through neutral light-grey pixels only (the picture is warm or dark; nothing the flood can't reach from outside is touched: 62.6% of the pixels), and the soft rim (4,226 pixels) given an alpha by unmixing it from the local checker grey. Inspected at full size on dark and light backgrounds: no halo. Then cropped to content and shrunk. |
| Classic Adventure | 1536 × 1024 RGBA, genuine transparency (about three quarters alpha 0, a soft aura kept as painted) | `media/classic.tga`, 512 × 256 | cropped to content (938 × 659) and shrunk to fit, centred |
| Personalize and Screen Fit | one 1774 × 887 RGBA sheet; the two pictures are separate runs of columns holding any alpha (126–811 and 925–1629), found by measurement | `media/personalize.tga`, `media/screenfit.tga`, 128 × 128 each | split at the clear gap; each cut to content and shrunk to fit |
| Compact Adventure | 1536 × 1024 RGBA, same kind as Classic's (a belt pouch with a scroll and a dagger) | `media/compact.tga`, 512 × 256 | built in Phase 5 with `--phase5`: cropped to content (a 226 × 252 picture centred in the 512 × 256 file, like Classic's) |

All TGAs are uncompressed 32-bit, bottom-left origin, 8 alpha bits (the format of every other `media/` file), power-of-two
sizes, with colour carried 2 px into the clear pixels so bilinear filtering shows no dark matte. Total shipped: about 1.2 MB (Compact's picture is 524 KB).
Nothing was recoloured, sharpened or generated; no replacement was made for anything missing.

Runtime: the three small pictures are registered in the icon registry (`Art.lua` adds `layoutEmblem`, `layoutPersonalize`
and `layoutScreenFit` to `R.Icons.list`) and drawn with `R.Icons.Apply`, so a file the game refuses falls back to
TwichUI's own emblem. Classic's and Compact's pictures are drawn by `Art.Apply` with the same rule (refused: hidden). A picture is
decoration only: with every file refused the whole wizard, an install included, still works (`test_layout_wizard.lua`
§10). Nothing is reserved or missing any more (`Art.Missing()` is empty). The sources' dimensions and what each needed are in the tool's header.

## Packaging, release and diagnostics

- `.pkgmeta` `move-folders`, `tools/release.py` (`WIZARD`, `ADDONS`, `LOAD_ON_DEMAND`, and `REQUIRED_DEPS`: the wizard
  requires `!!!TwichUI, TwichUI_Layouts`, every other load-on-demand addon only the core), `tests/test_release_tools.py`,
  `RELEASING.md` (six folders), and the git-ignored `tools/deploy.sh`.
- Diagnostics (`CLAUDE.md`, "Diagnostics coverage"): scopes `layoutwizard.load` (`LayoutsLauncher.lua`),
  `layoutwizard.build` (the first open) and `layoutwizard.preview` (each draw), and from Phase 5
  `layoutwizard.overlay.build` (the first time the full-size preview opens) and `layoutwizard.overlay` (each draw of it),
  registered in `DX.OPS` and `docs/diagnostics.md`; gauges `layoutwizard.events` (4 while open, 0 closed),
  `layoutwizard.frames` (does not grow when reopened), `layoutwizard.overlay.events` (3 while the preview is shown, 0
  closed) and `layoutwizard.overlay.frames` (frames and textures it keeps, bounded by the package); the addon's memory is read and reported (`Base.lua`, `Collect.lua` `ReadMemory` and `OURS`, `Export.lua`,
  `Findings.lua`, `Session.lua`, `Window.lua`). The plan, apply, verify and restore scopes are `layouts.*` (Phase 2),
  already around the engine calls the wizard makes. Nothing personal is in a report: the wizard stores picks (option ids)
  only.
- Not scoped, and why: the pages' text refreshes (each runs only on a click, a pick or an event while the window is open,
  with no per-frame work); `Model.Compat()` (a few reads); the footer; building the scene (`Scene.Build`, `LY.Elements`: table
  reads and arithmetic, cached until a pick, layout, scenario or the screen changes). No `OnUpdate` or timer is installed,
  and the only hook is one `Profiles.OnChange` listener per piece (the window's, the overlay's), added once.

## Checks

`tests/test_layout_wizard.lua` (with `tests/layouts_mock.lua`) drives the real window, through its buttons, with stand-in
frames, the real engine and a stand-in EllesmereUI of the real functions' shape. It covers: the `.toc`, files and that the
source has no minimap button, no Escape handler call, no code loaded from text and no login event; loading on demand, the
entries, and that failures are explained; that nothing opens by itself; every compatibility case (no, old, other-client,
newer-than-tested EllesmereUI; its first-run setup; an unreadable and a too-small and a narrow screen; combat); every step,
Back, the stepper, cancelling at each step and reopening; the preview's proportions for five screens and that its boxes
are the resolved geometry to scale; that a pick changes the preview, the plan, the payload and the key together; that
choosing changes nothing in the game; the confirmation's text; apply, the reload the player starts, the check after it and
the wizard opening on it; a reload the player made themselves; Restore (declined, confirmed, after its reload); setting up
again and restoring to before the first install; an interrupted install; a clean failure and a part-way failure; combat
(window, model, engine); a plan that went stale; a profile of the package's name that isn't ours; reopening six times
with no new frames, listeners or hooks; the gauges and scopes; saved wizard state that is junk, partly invalid, newer, or
a leftover note; a damaged, newer or other-character install record; the artwork (TGA headers, sizes, the reserved file
absent, every picture refused).
`tests/test_layouts.lua` §17 covers the engine side: every refusal of a malformed `choices` section, picks resolving into
the layers, the plan key and the record following the picks, and the accent read back by value (including a number that
went through EllesmereUI's serializer). `test_release_tools.py`, `test_perf_engine.lua` and the settings contract fixture
cover the wiring.

Mutations made by hand and reverted, each failing a test: apply without the shown key; pages rebuilt on every show;
saved picks not validated; a newer state overwritten; the wizard always opening after a check; never opening; no resume
note; a preview ignoring the viewport's proportions; events left registered; a preset allowed to turn things off; two
choices allowed to write one unit; the accent checked only for presence; combat not refused by the model; a refused picture
not handled; a missing EllesmereUI not blocking; the session surviving close; a pick that mutates the game; the record's
picks unchecked; the release tool accepting the wrong dependencies.

Measured offline (Lua 5.1 on the development machine, not the game): the wizard's code adds about 170 KB of Lua heap when
loaded; `LY.Plan` for the review takes about 32 ms and allocates about 8 MB of garbage (it is computed once per review, not
per click); the plan, while held, is about 2 MB and is released when the player leaves the review. In-game memory and CPU
are not measured: a `/tui perf` General capture with the wizard closed, and one opening it ten times, are among the
checks below.

### Phase 5 checks

`test_layout_geometry.lua` §8–§10: the variant mechanism on a synthetic layout (merge by id, the shared spec unchanged, caching,
every refusal, a variant for a layout the package lacks); Compact on nine screens × two densities (fits, on screen, never
under a minimum, fixed sizes kept); the author's own screen gives back what was captured (41 positions, every link offset, every
TwichUI place), the 1080p moves (bottom row, raid frames from the left edge, the bar on the meter's top), narrow chat above the
block, 1365 × 768 honestly not fitting; `LY.Elements` (sizes, the bar rule against the author's own 377 vs 375, notes, markers)
and every piece compared with what `Adapt` writes on five screens × two densities; the capture (no TwichUI side, nothing
personal, 11 shared modules proven by fingerprint, 7 + 7 own), and promoting a setting between the layers. `test_layouts.lua` §18:
both layouts through plan/apply/verify, the switch (same profiles, first snapshot kept, no profile added, four more switches),
unrelated data untouched, restore from either layout, narrow and small screens, the developer command (`compact`).
`test_layout_wizard.lua` §12–§17: both cards and the preview following at once, forty switches making nothing, choices and the
review and question naming the layout and saying it is a switch, apply/reload/resume/restore through a switch, the five
scenarios (what each shows, nothing moving, the tooltip place and its fallback, not remembered), scene = plan = miniature =
overlay = what the install writes, the overlay's source scan, click-through, inertness, Back/Exit/Escape/switch/scenario, combat,
profile change, wizard close, screen change, ten opens and closes making nothing, long text and overflow, narrow Compact, and
saved state with a layout. Mutations made and reverted, each failing a test: the overlay taking the mouse, variants ignored by
`Geometry.Spec`, the combat close removed, the profile listener removed, scenarios not filtering pieces, shared modules not
shared.

## Manual acceptance checklist (none done; on WoW: Forever)

1. `/tui layout` opens the window; it is complete without EllesmereUI's skins; Escape closes it; the Home and
   Troubleshooting buttons open it; no minimap or broker button exists; a new character gets no prompt.
2. The pictures draw (emblem, Classic, Personalize, Screen Fit) with no green or white square, with transparent
   backgrounds, at 1080p, 1440p and an ultrawide.
3. Welcome: the EllesmereUI line reads right (version, Forever build); with EllesmereUI disabled, Start is blocked with
   the reason; in combat, the line says so.
4. Each step; Back; the stepper; Close at each step changes nothing (compare `/tui` settings and EllesmereUI's profile list
   before and after).
5. Picks: each accent recolours the preview's outlines; Larger enlarges chat, the meter and the minimap boxes; the
   helpers cards select with a bar and "Selected".
6. Review matches what the apply then does: profile names, the account-wide note, the reload, "Left alone", "Not placed".
7. Apply: the question names both profiles; Cancel changes nothing; Apply makes both profiles and nothing reloads.
8. Reload now: after the reload the wizard opens on "Checked after the reload" (verified). A reload made with `/reload`
   instead prints the chat line and leaves the wizard closed.
9. The accent shows in EllesmereUI (its accent swatch reads the picked colour); the picked helpers are on in
   `/tui options`; the size you picked is the size you see; positions match the preview on your screen (screenshots).
10. Restore previous setup: the question lists what it does; after the reload the wizard says "Restored", EllesmereUI is
    back on your profile, the install's profiles are gone, your TwichUI profile is as it was.
11. Set up again with another accent: applies, reloads, verifies; Restore goes back to before the first install.
12. In combat: Apply, Restore and Reload now are refused with a reason; they work again after combat.
13. Interrupt (`/reload` the moment after Apply, or kill the client): next login says interrupted; Restore works.
14. Open and close the window ten times in a `/tui perf` capture: the `layoutwizard.events` and `layoutwizard.frames`
    gauges stay flat; `TwichUI_LayoutWizard` memory is reported.
15. A Forever EllesmereUI: the Retail-captured blobs load; the accent is read back (`accent:rgb` matches live).

## Phase 5 manual checks (none done; on WoW: Forever)

16. Step 2 shows both pictures with transparent backgrounds; clicking a card re-draws the miniature at once; nothing in
    EllesmereUI's profile list or TwichUI's profiles changes (compare before and after).
17. **See it full size** at 1080p, 1440p and the ultrawide: the boxes and pieces sit where the install then puts the real ones
    (apply, reload, screenshot, compare), including Compact's bottom strip, the bar on the damage meter and the party frames.
18. The dimming: is the live interface behind it too distracting? Click-through works (a world click, a target click, moving
    the camera); keys still work; Escape returns to the wizard; nothing of EllesmereUI is hidden or moved.
19. Combat: the button is refused in combat; pulling a mob with the overlay open closes it; a profile switch (`/tui` profiles)
    closes it; `/reload` with it open leaves nothing behind.
20. Switch layout in the overlay and in the wizard; apply Compact over Classic: the review says it is a switch, the same two
    profiles are rewritten, the check after the reload says verified, Restore goes back to before the first install.
21. Compact on the author's own screen reproduces their `TwichUI - Minimal Adventure` look (positions of bars, unit frames,
    cast bar, raid and party frames, the bar on the meter); on a 1920 × 1080 screen the bottom row sits on the bottom edge; on a
    narrower screen chat is above the strip.
22. TwichUI's pieces in Compact: class bars, marker bar, navigation arrow and food/drink sit where Classic's capture put them
    (D31); look at the markers in the overlay first, then in game. The food and drink proxy is also linked to bar 3 in
    Compact's layout links.
23. `/tui perf`: open the overlay ten times; `layoutwizard.overlay.events` and `.frames` stay flat; the addon's memory with both
    layouts' data loaded (about 1.6 MB of Lua tables offline) is reported.

## Phase 6 handoff

- **Retained overrides**: the wizard keeps the picks and the layout across installs, and switching layouts is an install again, so
  "kept" and "reset" can be shown in the review without changing the steps (`LY.Compose` already takes `retained` and `reset`).
  Module blobs differ per layout, so retention is per module blob and per registered position, as §6 says.
- **Per-layout TwichUI settings**: Compact shares Classic's TwichUI looks and places (D27). If the author wants Compact-specific
  TwichUI places, capture them from a separate TwichUI profile with `--twichui-profile` and put them in the variant layer: the
  composer already lets a variant's units win.
- **UI scale policy** (D12): a `ui-scale` choice would be a fourth choice; the plan, the review, the miniature and the overlay
  already follow the screen the geometry is resolved for, so they need the target scale's viewport. It needs the
  whole-`EllesmereUIDB` restore point (D3), and with it the **tooltip choice** can be offered (D5).
- **Positions not yet placed** (D32): the Battle Res frame (`centerX`/`centerY` storage), the Cooldown Manager's other bars,
  class power. Each needs a registered position with its own format, then an attach entry per layout.
- **Choices the schema already allows**: more enums (each names its `sets`), more presets (switches only).

## Open decisions raised in Phase 4

| # | Question | Recommended default |
|---|---|---|
| D21 | The TwichUI helper presets: which switches, which names (`on-screen`: class resource bars, marker bar, food and drink buttons; `finding-my-way`: those and Navigation) | As built; the author to confirm or change the set |
| D22 | The accent options (Aged gold, Class colour, Verdigris, Ember, Dusk blue) and their colours | As built (the three non-captured colours are proposals in TwichUI's palette); the author to confirm |
| D23 | The tooltip choice (cursor-following or fixed): not offered until account-wide units are managed (above) | Keep it out; build with D3 and D5 |
| D24 | A Welcome-dialog offer for the wizard | Not built; the wizard is on Home. Add a button only if the author wants it there |
| D25 | Re-running with the same choices re-imports the install's EllesmereUI profile (a module-blob package is always imported whole), replacing changes made in it since | As built, and the review says so; a "nothing to do" shortcut needs a content fingerprint of the live profile |

## Open decisions raised in Phase 5

| # | Question | Recommended default |
|---|---|---|
| D26 | The package has one pair of install profiles, `TwichUI Adventure` (EllesmereUI) and `TwichUI Adventure` (TwichUI), for both layouts (they were `TwichUI Classic` / `Classic Adventure`; nothing was installed under those) | As built: a layout switch is an install again, with no extra profile and one restore point |
| D27 | Compact's sources: EllesmereUI profile `TwichUI - Minimal Adventure` (confirmed by the author); TwichUI side shared with Classic (confirmed: the only TwichUI profile is `Default`) | As built |
| D28 | Compact's checked box is the core of the bottom strip (1091 × 157.5); the pet frame and bar and the stance bar follow it but are outside it | As built; the author to confirm, or widen it (which makes chat give way on every 16:9 screen) |
| D29 | Compact's narrow width is 1780 (Classic 1700) and below it chat rises above the strip at its full width | As built |
| D30 | The overlay dims the live interface instead of hiding it | As built; hiding UIParent would hide the preview and moving protected frames is not allowed |
| D31 | TwichUI's pieces (class bars, marker bar, navigation arrow, food and drink) are Classic's captured places in Compact too; class bars at (−385, −558) land inside Compact's strip | Look at the markers in the overlay on the author's screen and say which should move; capture them from a separate TwichUI profile if so |
| D32 | Not placed by the screen layer: the Battle Res frame, the Cooldown Manager's other bars, class power (left at the author's coordinates, which in Compact sit above the strip), and the pieces the preview has no size for | Register positions when the author wants them moved |

