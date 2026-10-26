# The layout setup wizard (Phase 4)

`TwichUI_LayoutWizard/` is a load-on-demand sibling addon (`RequiredDeps: !!!TwichUI, TwichUI_Layouts`, no saved variables
of its own) that lets a recipient review compatibility, pick the bundled Classic Adventure layout, choose a small TwichUI
helper preset, adjust two personal choices, review exactly what would change, apply it with a restore point, see it
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
| 2 | Layout | the Classic Adventure card (its picture, what it covers, a Preview-build tag) and the preview | nothing |
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

`TwichUIDB.layouts.wizard = { v = 1, picks = { [choice id] = option id }, resume = "install" | "restore" }`, beside the
install record (`layouts.install`, `Journal.lua`), covered by the same `layouts` entries in `TwichConfig.LOCAL` and
`RS.OWN_LEFT_OUT` (records, not settings: a backup or a share never carries them). Read-only reading, narrow repair
(`State.lua`):

- not a table, or `v` not a whole number ≥ 1: defaults; nothing is written by reading;
- `v` newer than this version: defaults are used and **a pick never overwrites it** (`test_layout_wizard.lua` §9);
- a pick that isn't an option of its choice goes back to that choice's default and the others are kept; unknown choices
  and a bad `resume` are ignored; the next pick saves a clean record;
- bounded: at most one entry per choice the package declares (3 for Classic).

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

## The preview

`Preview.lua` draws `LY.Geometry.Resolve`'s result (the same resolver the plan uses) on a frame whose proportions are the
recipient's viewport (`UIParent`'s width and height in its own units), fitted into 330 × 200: each managed component is a
box at its resolved centre offset and size, to scale, with sample shapes inside (text lines, bars, a minimap square) and
the picked accent as its outline. It says it is an illustration ("sample shapes in place of the real frames; the real look
is EllesmereUI's and TwichUI's own"), outlines overlapping or off-screen pieces in the warning colour and marks them with
"!" and a line, and says which pieces are shown but not applied (the objectives). The boxes are made once (7 boxes,
24 sample pieces) and moved on every draw. The class-colour accent uses the player's own class colour.

Offline: the geometry takes about 0.12 ms and a draw about 0.14 ms on stand-in frames (the real client's `SetPoint` and
`SetSize` cost more; not measured).

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
| Compact Adventure | 1536 × 1024 RGBA, same kind as Classic's | **not built** | reserved for Phase 5: `--phase5` builds it (`compact.tga`, 512 × 256, 524 KB) when that layout is |

All TGAs are uncompressed 32-bit, bottom-left origin, 8 alpha bits (the format of every other `media/` file), power-of-two
sizes, with colour carried 2 px into the clear pixels so bilinear filtering shows no dark matte. Total shipped: about 704 KB.
Nothing was recoloured, sharpened or generated; no replacement was made for anything missing.

Runtime: the three small pictures are registered in the icon registry (`Art.lua` adds `layoutEmblem`, `layoutPersonalize`
and `layoutScreenFit` to `R.Icons.list`) and drawn with `R.Icons.Apply`, so a file the game refuses falls back to
TwichUI's own emblem. Classic's picture is drawn by `Art.Apply` with the same rule (refused: hidden). A picture is
decoration only: with every file refused the whole wizard, an install included, still works (`test_layout_wizard.lua`
§10). **Missing or reserved**: Compact Adventure's picture (reserved, see above) is the only one; `Art.Missing()` reports
it. The sources' dimensions and what each needed are in the tool's header.

## Packaging, release and diagnostics

- `.pkgmeta` `move-folders`, `tools/release.py` (`WIZARD`, `ADDONS`, `LOAD_ON_DEMAND`, and `REQUIRED_DEPS`: the wizard
  requires `!!!TwichUI, TwichUI_Layouts`, every other load-on-demand addon only the core), `tests/test_release_tools.py`,
  `RELEASING.md` (six folders), and the git-ignored `tools/deploy.sh`.
- Diagnostics (`CLAUDE.md`, "Diagnostics coverage"): scopes `layoutwizard.load` (`LayoutsLauncher.lua`),
  `layoutwizard.build` (the first open) and `layoutwizard.preview` (each draw), registered in `DX.OPS` and
  `docs/diagnostics.md`; gauges `layoutwizard.events` (4 while open, 0 closed) and `layoutwizard.frames` (does not grow
  when reopened); the addon's memory is read and reported (`Base.lua`, `Collect.lua` `ReadMemory` and `OURS`, `Export.lua`,
  `Findings.lua`, `Session.lua`, `Window.lua`). The plan, apply, verify and restore scopes are `layouts.*` (Phase 2),
  already around the engine calls the wizard makes. Nothing personal is in a report: the wizard stores picks (option ids)
  only.
- Not scoped, and why: the pages' text refreshes (each runs only on a click, a pick or an event while the window is open,
  with no per-frame work); `Model.Compat()` (a few reads); the footer. No `OnUpdate`, timer or hook is installed.

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

## Phase 5 handoff

- **Compact Adventure**: build its variant (`tools/layout_capture.lua`, D1) and add its card to step 2; the wizard reads
  `Model.Layouts()` (one entry today) and `Model.TEXT`. Its picture source exists: `python3
  tools/make_layout_wizard_art.py --phase5` builds `compact.tga`; add `compact = { file, w = 512, h = 256, what }` to
  `Art.FILES` and drop `Art.RESERVED.compact`. Step 2 then needs a real choice between cards (`Pages.lua` `BuildLayout`
  draws one fixed card), and a variant pick belongs in the saved state and the plan key.
- **UI scale policy** (D12): a `ui-scale` choice would be a fourth choice; the plan, the review and the preview follow the
  screen the geometry is resolved for, so the preview needs the target scale's viewport. It needs the whole-`EllesmereUIDB`
  restore point (D3), and with it the **tooltip choice** can be offered (D5).
- **Choices the schema already allows**: more enums (each names its `sets`), more presets (switches only). A preset that
  needs to turn something off, or any value that isn't a switch, needs a deliberate schema change.
- The wizard keeps the player's picks across installs, so Phase 6's retained overrides can show "kept" and "reset" in the
  review without changing the steps (`LY.Compose` already takes `retained` and `reset`).

## Open decisions raised in Phase 4

| # | Question | Recommended default |
|---|---|---|
| D21 | The TwichUI helper presets: which switches, which names (`on-screen`: class resource bars, marker bar, food and drink buttons; `finding-my-way`: those and Navigation) | As built; the author to confirm or change the set |
| D22 | The accent options (Aged gold, Class colour, Verdigris, Ember, Dusk blue) and their colours | As built (the three non-captured colours are proposals in TwichUI's palette); the author to confirm |
| D23 | The tooltip choice (cursor-following or fixed): not offered until account-wide units are managed (above) | Keep it out; build with D3 and D5 |
| D24 | A Welcome-dialog offer for the wizard | Not built; the wizard is on Home. Add a button only if the author wants it there |
| D25 | Re-running with the same choices re-imports the install's EllesmereUI profile (a module-blob package is always imported whole), replacing changes made in it since | As built, and the review says so; a "nothing to do" shortcut needs a content fingerprint of the live profile |
