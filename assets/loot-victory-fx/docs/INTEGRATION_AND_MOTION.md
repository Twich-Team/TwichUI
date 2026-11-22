# TwichUI Loot Victory — Lighting & Magic FX Integration Specification

**Objective:** Match the luminous gold atmosphere of the originally approved victory-card mockup while preserving the current card's now-approved layout, readable item information, and existing successful animation implementation. This supplement provides *overlays only*.

## Coordinate convention and layering

Reference screenshot: 428 × 201 UI pixels. All rects below are **relative UI pixels** to the displayed card at that size, not framebuffer pixels. Scale with the actual card and UI scale. Verify offsets in the client instead of hardcoding global positions.

Layer order, rear-to-front:

1. Existing leather/bronze card backdrop and top frame.
2. Atmospheric underlight `fx_header_haze`, `fx_icon_gold_haze` (under title and icon; NOT over text).
3. Optional aura (`fx_icon_epic_ring`) around/behind item icon, clipped not to overlap item name.
4. Existing victory title, emblem and item information, above atmosphere.
5. Small additive highlights (`fx_header_bloom`, `fx_sweep_core`, `fx_glint_small`, particles), located away from text.
6. Normal tooltips and any interactive controls remain topmost.

Suggested anchor boxes from the 428×201 screenshot, for art-direction reference only:

| Element | x, y, width, height | Peak opacity / blend | Notes |
|---|---|---|---|
| `fx_header_haze` | 83, 17, 260, 43 | 0.30–0.45 / ADD | Behind YOU WON title |
| `fx_header_bloom` | 129, 23, 170, 29 | 0.50–0.80 / ADD | Brief burst, do not leave static |
| `fx_sweep_haze` | moving 70px-wide x=30→348, y=19, h=36 | 0.25–0.45 / ADD | Soft traveling underlayer |
| `fx_sweep_core` | moving 58px-wide x=30→348, y=23, h=30 | 0.65–1.0 / ADD | Bright traveling focus, clipped to trim/header |
| `fx_icon_gold_haze` | 37, 74, 76, 79 | 0.25–0.45 / ADD | Behind item icon |
| `fx_icon_epic_ring` | 39, 78, 66, 67 | 0.18–0.32 / ADD | Only for epic, low intensity; NOT a green rarity replacement |
| `fx_icon_bloom` | 40, 75, 70, 73 | 0.45–0.70 / ADD | Short arrival flash |
| `fx_emblem_burst` | centered around existing Need/Greed marker, approx 38x38 | 0.45–0.65 / ADD | One-shot behind emblem |
| `fx_glint_small` | 10–19px | 0.7–1.0 / ADD | Short-lived trim glint |
| `fx_particle_star_4point` | 10–16px | 0.75–1.0 / ADD | A few fixed paths, not full-frame particles |
| `fx_particle_mote_medium` | 7–11px | 0.4–0.65 / ADD | Light dust, lower intensity |

Opacity values are **starting tunables**, not measured in-client. The model should inspect the actual texture and avoid multiplying already faint alpha into invisibility. Since ADD blending changes apparent brightness across clients, tune while looking at game captures.

## Recommended first-pass runtime subset

Use **at most 11 FX textures initially**, with pooling/reuse:

- Atmosphere: `fx_header_haze`, `fx_icon_gold_haze`
- Reveal: `fx_header_bloom`, `fx_emblem_burst`, `fx_icon_bloom`
- Sweep: `fx_sweep_haze`, `fx_sweep_core`
- Accent: `fx_glint_small`, `fx_particle_star_4point`, `fx_particle_twinkle`, `fx_particle_mote_medium`

`fx_icon_epic_ring` is an optional 12th for epic preview once the common look works. All other assets are alternate/optional references. Do not layer every haze simultaneously.

## Recommended one-shot timeline

| Seconds | Animation intent and texture usage |
|---|---|
| 0.00–0.25 | Existing result transition. Rise `fx_header_haze` from 0 to ~0.35; `fx_icon_gold_haze` from 0 to ~0.3. Keep text readable. |
| 0.20–0.53 | `fx_header_bloom` quick rise to ~0.7, then decay. `fx_emblem_burst` appears for ~0.25s. These are behind the title/emblem. |
| 0.38–1.05 | Gold sheen travels left to right. Move `fx_sweep_haze` and `fx_sweep_core` **together** across trimmed header, not a bright full-card flash. Highlight core should remain plainly visible. |
| 0.55–1.35 | Choreographed 4–6 particles using three small sprite assets. Fixed anchors near emblem and item icon. Up/out drift 8–28 UI px. Fade to 0. |
| 0.90–1.50 | Icon arrival `fx_icon_bloom` peaks and fades. One small `fx_glint_small` punctuation near icon frame. |
| 1.65+ | Fully settled card, no active FX animation. Header haze at 0.12–0.20 if desired, but no continuing OnUpdate. |
| Hold/exit | Keep item/title readable. Existing dismissal schedule and cleanup, no looping. |

### Example particle path sketch (card relative to 428×201)

The following are design targets, not absolute APIs or in-client measured positions. Keep all sparks outside item-name area:

- Star A: start (102,91) → (119,77), 0.25s, peak at 0.67s; scale 13→9 UI px.
- Star B: start (56,84) → (42,69), 0.30s, peak at 0.74s; scale 11→7 UI px.
- Twinkle C: start (292,40) → (312,30), 0.35s, peak at 0.88s; scale 13→8 UI px.
- Mote D: start (92,116) → (113,99), 0.45s, peak at 0.96s; scale 8→6 UI px.
- Mote E: start (125,46) → (109,34), 0.45s, peak at 1.05s; scale 8→5 UI px.

All path easing should be smooth and deterministic. No new global particle manager, no random particle storm, and no effect touching item text.

## Implementation guardrails

- Existing card dimensions, margins, rarity text, roll state, upgrade badge, and font hierarchy remain unchanged except tiny anchor adjustments if objectively needed.
- Any glow behind text must be constrained or dim enough not to reduce legibility.
- Pool textures and stop animation work on hide/interrupt; no background OnUpdate loop when idle.
- Do not derive victory from chosen Need/Greed action. Preserve confirmed-win logic and selective Blizzard alert suppression.
- Use the same view/state for preview and live result; Preview button must reset all glows/particles to initial conditions before replay.
- Respect OFF/SUBTLE/FULL: OFF = no effects; SUBTLE = atmosphere + title bloom + single sweep + 2–3 sparks; FULL = all recommended one-shot layers with at most 6 sparks.
- If additive blending washes out the top border, reduce density or opacity of the `fx_header_bloom` layer rather than increasing darkness of the entire card.
- If any sprite looks wrong due to TGA/alpha differences, verify path/size/texcoords, blend mode and render ordering in WoW Forever and take screenshots at normal UI size.
- Do not ship source atlases/PNGs, illustration previews, or docs inside the addon distribution unless the repository deliberately supports such documentation sources.

## Acceptance checks

- The gold sweep is clearly visible at 100% UI scale; title text is legible throughout.
- A recognizable bright white-gold glint appears for at least one small time interval around the emblem or icon.
- The ambient haze is noticeable but does not cause flat orange fill.
- No detached square alpha edges, red/yellow fringe, black matte, or clipping appear on screenshots.
- Need and Greed both work; quality-specific accent stays coherent; glow does not imply an incorrect rarity.
- Preview restarts identically; repeated quick previews and win queue do not retain effects or play extra audio.
- Animation OFF leaves the current clean result card unaffected.
- Stable FPS, no idle texture churn, zero extra draws after card is hidden.

## Verification limitation

All textures have been exported and programmatically checked for 32-bit alpha, matching PNG/TGA decode, transparent borders and power-of-two dimensions. Their *visual integration is unverified* until a real World of Warcraft Forever client has displayed them. PNGs are supplied for authoring; prefer TGA for client loading, subject to actual client tests.
