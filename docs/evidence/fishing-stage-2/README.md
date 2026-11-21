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
| `castbar-*.png` | The cast bar at 2x: label, seconds left from the channel's own times, amber fill, and session figures and prompts |

Regenerate: `python3 tools/render_fishing_hud.py` (writes to `test-output/fishing-captures`). `SHA256SUMS` lists these files.
