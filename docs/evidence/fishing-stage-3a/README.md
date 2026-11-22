# Fishing Journal (Stage 3A): offline captures

Screenshot-reviewed layout captures of the Journal, **not game screenshots**. `tools/render_fishing_journal.py` runs
`tests/journal_capture.lua`, which loads TwichUI_Fishing's real Journal in the simulated client (tests/fishing_mock.lua,
tests/ui_widgets.lua) over invented records (a long-time fisher: 188 sessions, 6,531 fish, 14 kinds, 6 zones, clams and pearls),
and draws every visible texture and font string at its resolved place with the real textures (`TwichUI_Fishing/media`) and
fonts, at 2x, over a dim painted night.

What differs from the game: the world behind is painted; the item icons are the texture pack's illustrative fish and clam art
(`assets/fishing/standins`), because the game's icons are not available here; text metrics, filtering and blending are
approximated; wrapped text is wrapped by the renderer. The approved mockup's Journal shows value columns; Stage 3A shows none
(no Workshop, no prices), with the layouts leaving room for them.

| Page | File |
|---|---|
| Overview | `journal-overview.png` |
| Sessions | `journal-sessions.png` |
| Collections | `journal-collections.png` |
| Locations | `journal-locations.png` |
| Treasures | `journal-treasures.png` |
| Session summary | `journal-summary.png` |
| Empty (nothing fished yet) | `journal-empty.png` |

Regenerate: `python3 tools/render_fishing_journal.py` (writes to `test-output/journal-captures`). `SHA256SUMS` lists these files.
