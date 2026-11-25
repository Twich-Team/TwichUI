# TwichUI Fishing, Stage 2: offline captures of Fishing Mode

**Label: screenshot-reviewed (offline).** These are not game screenshots and not real-client evidence.

How they were made: `tools/render_fishing_hud.py` runs `tests/fishing_capture.lua`. That script loads TwichUI_Fishing in the
simulated client (`tests/fishing_mock.lua`, `tests/ui_widgets.lua`) and plays a session through Stage 1's key: casts,
catches, misses, and clams opened by the key. It records every visible texture and font string with its resolved place on a
1366 x 768 screen. The renderer draws that record at 2x with the addon's real textures (`TwichUI_Fishing/media`) and fonts
(`!!!TwichUI/media/fonts`), and these copies are scaled to 1x. The cast bar crops stay at 2x.

What differs from the game:

- The backdrops are painted gradients: bright snow and water, a moonlit night, and the mockup's sunset palette.
- The item icons are stand-ins (`assets/fishing/standins`, the texture pack's illustrative art), because the game's own
  icons are not available outside it.
- Text metrics, filtering and blending are Pillow's, not the client's.
- The scene's item names and qualities are its own.
- The session start is moved back so it reads as 42 minutes.
- The current line is staged 16.5 s into a 30 s channel.
- Notifications are held 8 s, so both are in the frame.

| File | Shows |
|---|---|
| `immersive-bright.png`, `immersive-dark.png`, `immersive-sunset.png` | Immersive: the cast bar mid-line, the catch list on the right (catches, other treasures, totals), and a treasure notice and a catch notice |
| `compact-*.png` | Compact: the cast bar and notices only |
| `castbar-*.png` | The cast bar at 2x: label, seconds left from the channel's own times, the warm gold fill, the session figures with the pack's glyphs (bobber, fish mark, feather), and prompts |
| `compare-mockup.png` | The approved mockup's emblem, catch list, notification and cast bar (left) beside the same pieces of `immersive-sunset` (right) |

## Settings page (simulator-tested, structural)

`settings-*.png` show the real settings window, drawn by the repository's simulator lab. It was run as
`SIMLAB_ASSETS=0 SIMLAB_EXTRA=TwichUI_Fishing bash tools/simlab/run.sh settings fishing`, with `SIMLAB_SETTINGS_TASK` 2–5
for each tab: wow-ui-sim v0.1.37, Forever UI 1.60.1.70532, and no game install, so Blizzard art and fonts are absent. Going
to the page loaded TwichUI_Fishing in the simulator. Each run passed its 21 to 22 handler and state checks: the tabs fit,
the dropdowns open and close, the page is searchable, and reopening reuses it. The simulator draws every addon font in
Friz Quadrata, so these are structural captures, not a visual or text-wrapping review.

| File | Shows |
|---|---|
| `settings-home.png` | Home: Fishing among the featured features ("Not loaded yet" before a visit), and in the page list under Adventure |
| `settings-fishing.png` | Fishing: status, the switch, your keys, Open Key Bindings, Start Fishing Mode, your gear, Put things back |
| `settings-assistance.png` | Fishing assistance |
| `settings-mode.png` | Fishing Mode: presentation, camera, fading, motion, prompts, the gamepad pulse (with its note), the emblem |
| `settings-fading.png` | Interface fading: the groups, notices, opacity, Include EllesmereUI and what was detected, what can be faded now |
| `settings-hud.png` | The HUD: pieces, sizes, rows, order, the value area, Place on screen, Reset positions, Try Fishing Mode |

## Against the approved mockup

`compare-mockup.png` puts each HUD piece beside the mockup's.

- **Matches:**
  - The emblem (the pack's logo).
  - The catch list's heading, the game icons in the pack's bronze frame with the quantity on the corner, the names, the
    warm "N caught" lines, the large "×N", the fine rules between the rows and under the headings, and Other Treasures.
  - The notification: the pack's frame and band, lengthened for long names, with the ivory "Caught!", the gold "×2" and the
    warm light behind the frame.
  - The cast bar: the pack's bar, "Fishing…" with its seconds, the warm gold fill in the trough, and the figures under it
    with the pack's glyphs.
- **Different on purpose:**
  - No gold figures. "Estimated Value" says "Not available yet" until Stage 3 connects a valuation, and per-row values
    come with it.
  - A line of key prompts under the cast bar (`/tui fish prompts off` hides it).
  - A faint feathered shade under the list and the bar's lines, which keeps them legible over bright scenery (see
    `immersive-bright.png`).
- **Different because of the supplied art:**
  - The pack's cast bar has the hook painted in, where the mockup draws it beside the label.
  - The pack's logo has its plaque.
  - The treasure rows use the same bronze frame as the catches; the mockup shows them bare.

Regenerate: `python3 tools/render_fishing_hud.py --compare <the approved mockup>` (writes to `test-output/fishing-captures`). `SHA256SUMS` lists these files.
