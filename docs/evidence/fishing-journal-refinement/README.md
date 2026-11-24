# Fishing Journal refinement: offline captures

Screenshot-reviewed layout captures, **not game screenshots**. `tools/render_fishing_journal.py` runs `tests/journal_capture.lua`,
which loads TwichUI_Fishing's real Journal in the simulated client over invented records (188 sessions, 15 kinds, 6 zones, with
where each fish was caught since location recording began, clams and pearls, a session that spanned three zones), and draws every
visible texture and font string at its resolved place with the real textures and fonts, at 2x over a dim painted night.

Differs from the game: the world is painted; item icons are the texture pack's illustrative stand-ins (`assets/fishing/standins`);
text metrics, filtering and blending are approximated; wrapped text and the two-line limit of a long name are drawn by the
renderer. The game's fonts are used where the files are here (`!!!TwichUI/media/fonts`).

| Capture | Shows |
|---|---|
| `journal-overview.png` | the Overview |
| `journal-sessions.png` | a session that spanned three zones: "Stranglethorn Vale +2", the zones with their catches, items kept apart from catches |
| `journal-collections.png` | a chosen species with where it was caught (zone rows with quantities and dates, the unplaced "Earlier catches") |
| `journal-collections-longname.png` | a very long fish name (two lines and an ellipsis), page 2 of 2 |
| `journal-locations.png` | a chosen zone: figures, how much of its items the breakdown covers, its fish, recent sessions |
| `journal-locations-unknown.png` | the "Unknown zone" (catches where the game gave no zone) |
| `journal-treasures.png` | containers and their confirmed contents |
| `journal-summary.png` | the session-completion card for that multi-zone session |
| `journal-empty.png` | nothing fished yet |

Regenerate: `python3 tools/render_fishing_journal.py` (writes to `test-output/journal-captures`). `SHA256SUMS` lists these files.
