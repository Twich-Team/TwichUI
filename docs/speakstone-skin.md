# SpeakStone skin

The settings are a page of their own, **Addon skins > SpeakStone speech frame** (a nested page of the Addon skins
page, which keeps a short pointer to it).

An optional look for SpeakStone's speech frame (`modules/SpeakStoneSkin.lua`, `TwichUI_Settings/pages/SpeakStone.lua`,
`diag/SpeakStoneSkin.lua`). Written against SpeakStone Forever - Main 3.1.6 (Interface 16001), `SpeechFrame.lua`.
Off by default. A visual finish only: SpeakStone keeps its narration, queue, timer, text, dragging, position, size,
lock and visibility. Nothing is verified in the game yet (see the checklist).

## What SpeakStone's frame is (read from its source, not the screenshot)

| Piece | What it is | Where |
| --- | --- | --- |
| `SpeakStoneSpeechFrame` | a plain `Frame` (no template), global name, `UIParent` child | made lazily by the local `Build()` |
| band, top and bottom hairline | three textures on the frame (`BACKGROUND`, `BORDER`, `BORDER`) | **not exposed** (locals) |
| `frame.portrait`, `frame.portraitMask` | an `ARTWORK` texture and one `MaskTexture` (circle) shared by every portrait it makes | fields |
| `frame.name` | `FontString`, `GameFontNormalLarge`, one line, truncates | field |
| `frame.text` (in `frame.scroll`) | `FontString` on the private Font object `SpeakStoneSpeechTextFont` (13, spacing 2) | field |
| `frame.controls.time`, `.pause`, `.stop`, `.replay`, `.next`, `.gear` | a `FontString`, four `UIPanelButtonTemplate` buttons, a plain button | fields |
| `frame.close` | `UIPanelCloseButton` | field |
| `frame.progress` | `StatusBar` with one `BACKGROUND` track texture | field; the track is a local |
| `frame.lineHeight`, `frame.filledFor` | what `Fill()` multiplies by; which clip the text is laid out for | fields |

Facts the integration rests on:

* **Lazy.** `Build()` runs on the first clip, the `/ss frame` sample, a queued quest's portrait capture or the
  right-click menu. There is no global to hook before that, and SpeakStone's `addon` table is private.
* **SpeakStone never restyles after `Build()`.** It `SetText`s the time and the Pause/Resume label every 0.1 s, and
  `Fill()` sets the text area and the frame height (`130 + (lines - 4) * lineHeight`) once per clip or setting.
  `ApplyPosition()` (`SetScale`, `ClearAllPoints`, `SetPoint`) is the last thing `Build()` does and is rerun when the
  player picks a size or resets the position.
* **Plain frames.** Nothing in it is secure or protected, so it is restyled in combat too.
* `frame.filledFor = nil` is how SpeakStone itself asks for a new layout (`SpeechSettingChanged("speechFitText")`).

## How it works

* **Finding the frame.** `Build()` calls `CreateFont("SpeakStoneSpeechTextFont")` exactly once, after it has made the
  frame. A post-hook on the global `CreateFont` (one string comparison per call) hooks the frame and a zero-delay
  look is a fallback. The frame is hooked on `SetScale` (the end of `Build`, before any text is laid out, so the skin
  is drawn before the first measurement) and `SetHeight` (the end of `Fill`). All three hooks are installed once
  (`hooksecurefunc` cannot be removed) and check the switch.
* **Height.** `Fill()` sets the height from its base of 130. The `SetHeight` hook sets it again to the rows above and
  below the text area: padding, the controls row, the name, the gap, the text area, the progress line, padding, or
  the portrait's column, whichever is taller. `frame.lineHeight` is set to `text size + line spacing` (its own sum,
  13 + 2) so the four-line area fits the font; the text area keeps four lines (or all of the text, with
  SpeakStone's "Show all the text").
* **Drawn off SpeakStone's frame where it can be.** One child frame (`BackdropTemplate`, one level under the frame,
  no mouse) carries the background, border, portrait ring and progress track. MenuStyle draws the look on it.
* **Recorded, then put back.** Before the first change every piece SpeakStone made is recorded (anchors, sizes,
  alphas, font file/size/flags/object/colour/spacing, button font objects, state-texture tints, bar colour). Turning
  the skin off puts those back and clears `filledFor`, so SpeakStone lays out again with its own numbers on the next
  0.1 s tick. No reload is needed.
* **No per-tick work.** No `OnUpdate`, ticker or polling. Settings changes are coalesced (0.15 s) into one pass; a
  pass that changes nothing in the layout (a colour) neither re-anchors anything nor clears `filledFor`.
* **Errors.** A pass runs under `pcall`; on an error the frame is put back as it was, the error goes to the game's
  handler, and nothing is tried again until the switch is turned off and on.

## Surfaces

| Surface | Handling |
| --- | --- |
| Frame background and border | MenuStyle look on our child frame; SpeakStone's band and hairlines faded and hidden (every `Texture` region of the frame itself except the portrait and the captured portraits; no draw layer is relied on) |
| Speaker name, dialogue, time | font file and size and colour per string; dialogue spacing; SpeakStone's own inline colours (a quest title in grey) are left |
| Pause, Stop, Replay, Next | template art and highlight faded; flat fill in the button's own Normal/Pushed/Disabled textures (the game switches them), thin edge, hover tint on the highlight layer, label fonts through three Font objects of ours; width widened only if a label would not fit |
| Settings (gear) and close | art kept and tinted (`SetDesaturated` + vertex colour); clicks, tooltips and states are the game's |
| Close button, frame right-click | **Close with a right-click** (on by default): the close button is made invisible and click-through (`SetAlpha(0)`, `EnableMouse(false)`; it still exists), and the frame's `OnMouseUp` is replaced by one that calls `close:Click()` on a right-click, so SpeakStone's own `Dismiss` runs. Its right-click menu is then only on the gear. The original script and the button's alpha and mouse state are put back when the setting or the skin is turned off. The controls row moves out to take the button's place. |
| Portrait | anchor, size, ring (a masked disc behind it), round/square (SpeakStone's one shared mask is given a plain white file for square), hidden = made 1 px and alpha 0 (SpeakStone shows/hides it itself every clip) |
| Progress line | height, fill colour, track colour (ours drawn, SpeakStone's faded), hidden |
| Settings window, tutorial, quest library | not touched |

## Defaults

Warm umber background `ff241b13` at 90 %, 1 px bronze border `ff8c6e38` at 90 %. Speaker: TwichUI's title face
(Cinzel; falls back to SpeakStone's own font where it is not registered, which LibSharedMedia does for non-Western
clients) 16 px in muted gold `ffd4b05c`. Dialogue: SpeakStone's font 13 px in ivory `ffeee3c4`, line spacing 3.
Time: 11 px in stone `ff9e9482`. Buttons: label `ffe3d6b4`, fill `ff2c2218`, edge `ff6f5a30`, hover accent `ffd4b05c`,
11 px. Portrait: 72 px round, 2 px ring `ff8c6e38`. Progress: 2 px, fill `ffc9a24a` at 90 % (SpeakStone's own
strength), track `ff4a3a22`. Padding 12 (at which every offset is SpeakStone's own).

## Settings (common first; Advanced behind "Show advanced options")

* **Switch**, **Sample line** (SpeakStone's own `/ss frame`, no narration).
* **Look**: background color, opacity, border color; Advanced: background texture, border texture, thickness, opacity.
* **Text**: speaker font, size, colour; dialogue font, size, colour; time colour.
* **Controls**: label, fill, border and hover accent colours; close with a right-click (hides the close button).
* **Portrait**: show, size, shape, ring colour; Advanced: ring thickness.
* **Progress line**: show, fill colour, track colour, thickness.
* **Advanced**: time font and size, button font and size, line spacing, padding.
* **Reset appearance**: the look and the style (`ui.speakstoneSkin`, `ui.speakstoneSkinStyle`) only. Not the switch,
  SpeakStone's settings, its position and size, or anything else of TwichUI.

Saved: `modules.speakstoneSkin` (off by default), `ui.speakstoneSkin` (MenuStyle's look) and
`ui.speakstoneSkinStyle` (only values the player changed). Not part of configuration sharing or backups.

## Status and diagnostics

`Skin.Status()` codes: `off`, `speakstone-missing`, `speakstone-disabled`, `waiting` (SpeakStone has not built its
frame yet), `unsupported` (a piece the layout needs is not there; nothing is changed), `error`, `active`. The
troubleshooting section (`/tui diagnostics`, "SpeakStone skin") reports flags and counts only, never the text or
the speaker.

## Limitations

* Only SpeakStone Forever - Main's speech frame. `SpeakStone_Forever_Chatter` is audio data and has no UI.
* The band and hairlines are found as "every Texture of the frame except the portraits" and the track as the bar's one
  background texture, not by name; a different SpeakStone may match differently.
  The track not being found leaves it drawn as SpeakStone draws it, under ours.
* The frame's width is SpeakStone's (660 at its size scale); only height is the skin's. There is no narrow-width
  fallback layout: the controls sit on their own row above the name, as SpeakStone's do, and the name truncates.
* The hooks stay installed until a reload once the skin has been on; they do nothing while it is off.
* A hidden portrait is 1 px and invisible, not removed.
* SpeakStone's gear tooltip still says "Also right-click the frame." for its menu; with right-click closing on, that line is
  not true. It is SpeakStone's own text and is not edited.
* Everything about how it looks in the game, and combat, is unverified.

## In-game checklist (nothing here has been run)

Turn on Display Lua Errors. After each group, `/tui diagnostics`.

1. **Absent / disabled.** Without SpeakStone: TwichUI loads, the page says "not installed", no error. With it turned
   off in the AddOns list: "turned off".
2. **Load order and first sight.** Skin on, `/reload`, `/ss frame`: the sample is skinned on its first appearance
   (no flash of the native band). Also: skin on, first quest narration instead of the sample.
3. **Switch live.** `/ss frame` open; turn the skin off then on, five times: native look comes back each time, then
   ours; no error, no second copy of anything; `/tui diagnostics` shows the same three hooks.
4. **Text.** Short and long dialogue, "Show all the text" on and off, a long speaker name and a long quest title,
   each at SpeakStone's four sizes: nothing clipped or overlapping, the frame as tall as its content, no jump on
   every tick.
5. **Controls.** Pause/Resume (label changes, button does not clip), Stop, Replay, Next (queue two quests), gear
   menu, close: each does what it did. Hover, press and disabled looks read clearly.
6. **Progress and timing.** The line follows the voice; the time text counts; nothing resets colour mid-clip.
7. **Dragging and position.** Drag, lock, reset position, change size from the menu: the position is SpeakStone's,
   the thin lines stay one pixel.
8. **Portrait.** NPC portrait, queued quest portrait, a book (icon fallback); square and round; hidden.
9. **Settings.** Drag every slider and colour: no error, one redraw after you stop; the text is not re-laid-out by a
   colour change; fonts that SpeakStone's locale needs still draw.
10. **Combat.** Change a colour and a size during combat with the frame up; nothing errors, nothing is blocked.
11. **Other skins.** RestedXP skin, Chronicle, Food and Drink: unchanged.
12. **Memory.** `/reload`, wait, note `GetAddOnMemoryUsage`; play twenty clips; note again. Growth beyond the first
    clip points at a leak (nothing has been measured).
