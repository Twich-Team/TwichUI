# TwichUI — Loot Victory animation implementation specification

## 1. Product constraints

- Transform the existing loot-roll card into a won result **at the same location**; do not create an unrelated second toast.
- The final design target is ~460×200 UI px; support user-adjusted scale; do not stretch the art disproportionately.
- State must be derived from **confirmed self-win result** (Need/Greed), not from pressing a button.
- If the game client emits multiple rolls, serialize or stack cards with non-overlapping positions; never lose wins.
- Respect combat restrictions and any relevant UI taint constraints. Do not hide global alert containers indiscriminately.
- Only suppress the native **matching loot-winning alert** when custom presentation is reliable; retain other Blizzard notifications. If a safe narrow suppression is impossible on Forever, document and use a non-suppressing fallback rather than a fragile global hook.

## 2. Layout in a 460×200 UI card

Coordinates are illustrative and relative to the top-left at 1.0 scale:

| Element | Position and size | Notes |
|---|---|---|
| Base frame | x0 y0, 460×200 | `loot_won_frame.tga`, crop UV to 444/512 height |
| Title | centered, y~13 | `YOU WON!` render as game font, 25px visual scale, gold ivory |
| Need/Greed emblem | x134 y10, ~30×30 | No pop overshoot; fade in only |
| Item icon | x49 y74, 50×50 | Game item texture; quality border generated in Lua |
| Quality halo | x35 y54, 71×71 | Behind icon, fixed alpha 0.3–0.5 |
| Item name | x116 y73 | Game quality color, truncate safely |
| Item subline | x116 y98 | e.g. `Shoulder · Uncommon` |
| Win method | x116 y118 | e.g. `Need roll: 87`; do not invent roll value |
| Footer | x47 y160 | Conditional runtime status; do not assert inventory prematurely |
| Gold sheen | clipped top rim only | `rim_glint`, never across text |

## 3. Precisely timed one-shot motion

- **0–200 ms:** resolve, input buttons alpha 1→0, keep card anchored. Prevent further clicks.
- **150–450 ms:** title/emblem alpha 0→1; translate only +2 UI px downward to settled position; no bounce/scale overshoot.
- **350–800 ms:** one gold highlight follows metal top trim left→right; motion easing `smoothstep`; texture only over trim, masked/clipped if supported; **do not cross item text**.
- **450–1200 ms:** 5 fixed particles anchored around icon; positions are preauthored deterministic offsets: `(-8,-4)`, `(14,-7)`, `(7,12)`, `(-15,10)`, `(22,3)` UI px. Each moves 8–12 px upward; each size ≤13 px; fade to zero; no random spawning.
- **480 ms:** optionally play one muted chime `loot_win_victory.ogg` / `loot_win_greed.ogg`; once only, on SFX; respect settings. No overlapping repeated sounds for multiple wins.
- **1200–3700 ms:** static and fully readable; no looping idle effects.
- **3700–4000 ms:** fade whole card (0.3s) and recycle.

Use a client-time-driven `OnUpdate` animator with clamped `dt` and deterministic curves, not per-frame absolute pixel increments. Stop updates immediately after the rest state is reached; resume only to fade. Handle interrupted animation, UI scale and disabled animations safely.

## 4. Settings

- Replace default loot-winning result (if client-compatible and selectively suppressible): ON/OFF.
- Celebration intensity: Off / Subtle (default) / Rich (same sprite system, no new random particles; at most 7).
- Sound: ON/OFF (default ON if desired after game test); use SFX channel, do not play on the master channel.
- Duration: defaults 4s, user option if existing UI patterns permit.
- Preview button with a *fake* result state; must not trigger game-loot APIs or native event suppression.

## 5. Art loading / fidelity

- Use the provided 32-bit RGBA `.tga` exports; keep PNG masters for editing. Do not use the labeled concept storyboards as runtime textures.
- Transparent PNG/TGA must preserve straight alpha; avoid visible black fringe. Try BLEND with existing UI APIs; use additive blending only on spark textures if visually needed.
- Do not recolor the entire card by quality. Only game item border, halo and a modest title accent.
- The image resolution is intentionally power-of-two; crop the padded transparent area via manifest UVs.
- Use texture sizes in the manifest and a shared central texture-path constant; avoid string typos across UI modules.
- Preserve source attribution/documentation in the repo. Do not add huge raw concept sheets to addon shipping assets.

## 6. Acceptance criteria and verification

1. Card is readable at ~460×200 and UI scale down to ~0.75; no clipping or label overlap.
2. Need/Greed win shown accurately; no false win from roll selected but lost.
3. Lost/pass/disenchant/uncontested or no-result cases do not create false victory.
4. Client native matching won alert absent if safe suppression enabled; unrelated alerts still work.
5. Two near-simultaneous wins do not overlap improperly or misattribute item details.
6. CPU remains idle after animations; no persistent `OnUpdate` every frame for invisible cards.
7. Animation disabled falls back to static result; sound disabled truly silent.
8. Tooltip/item link function as before, if the existing card supports it.
9. Show correct quality tint; names with long localizations truncate cleanly.
10. Must validate textures and sound on **WoW Forever** before release; no assumption that the client matches current retail.
