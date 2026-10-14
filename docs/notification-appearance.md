# Notification appearance

How the four notification cards look: fonts, text size, colors, opacity, the accent rule and an optional
backdrop. Not when a card appears, what it says, where it sits, or its sound.

Code: `!!!TwichUI/modules/NotifyLook.lua` (settings, resolution, drawing helpers), the four renderers
(`Arrival.lua`, `Training.lua`, `FriendLogin.lua`, `WelcomeBack.lua`), the coordinator (`Notify.lua`), the settings
page `TwichUI_Settings/pages/Notifications.lua` (tab "Appearance"), sharing in `setup/TwichConfig.lua`.
Tests: `tests/test_notify_look.lua`, plus sections in `test_settings_window.lua` and `test_twichui_share.lua`.

## The four renderers are not one renderer

They share fonts, the bronze rule and the coordinator, but each lays itself out:

| Card | Parts | Layout |
| --- | --- | --- |
| Zone arrival | title (zone, or a smaller place), rule, smaller place, territory line | centered, 600 x 120 |
| New training | title, rule, spell rows (1 or 2 columns, rank/level inline), foot line | centered, 520 wide, height by rows |
| Friend login | faction mark, name, rule, "Online as ..." | left aligned, 360 x 64 |
| Welcome Back | title, rule, "Last noted ..." line, detail line, Open Chronicle link | centered, 520 x 96 |

So there are three text **roles**: *title*, *body* (the spells; the place on Welcome Back) and *detail* (everything
quieter). Zone and friend cards have no body, so a body color is neither offered nor accepted for them.

None of the cards had a frame or backdrop. A backdrop is new, drawn behind the text only, and its opacity defaults to
0, which is exactly the old look.

## Settings

| Setting | Values | Default (= the old look) |
| --- | --- | --- |
| Title font, Text font | LibSharedMedia name or `default` | `default`: each card's own face |
| Text size | 80-140 (% of each card's own sizes) | 100 |
| Text outline | shadow, none, outline, thick | shadow (the soft dark edge) |
| Title / Main text / Detail color | AARRGGBB | the cards' parchment, parchment, stone |
| Text opacity | 30-100 | 100 (text only) |
| Accent color, Accent opacity | AARRGGBB, 0-100 | bronze, 100 (the rule and its gold mark) |
| Backdrop color, opacity, padding | AARRGGBB, 0-100, 4-20 | umber, **0**, 10 |

Why a text *scale* and not a point size: the cards' sizes differ (30, 20, 18, 17, 15, 13). A percentage keeps their
proportions and keeps the default exactly the old look. Width and padding of the cards themselves are not offered:
a card grows (never shrinks) with the text, which is the only layout change that is safe for the coordinator's
overlap rules.

Text opacity and backdrop opacity are separate; the rule has its own; the faction mark and territory tint are
unaffected. Bounds: text opacity cannot go below 30 so a card stays readable.

Things that keep their color on purpose: the territory line's tint (it means friendly/contested/hostile), and the
Open Chronicle link's resting and hover colors (they say it is clickable). Both follow the font, size and opacity.

## Shared look and per-card look

- `ui.notifyLook`: the shared look. Every card follows it.
- `ui.notifyLookArrival/Training/Friend/Welcome`: a card's own look, used only while its `own` is true.

Turning a card's own look on **copies** the values it has kept (or, for new ones, the shared look's) into a complete
look. Later changes to the shared look do not reach it. This is the simplest model that is honest: the page shows
exactly what the card is drawn with. Turning it off keeps the values for next time; "Reset this card" forgets them;
"Reset the shared look" leaves cards with their own look alone. Neither reset touches whether a card is on, sounds,
positions, history or any other page.

Per-key inheritance (an override that is a sparse patch over the shared look) was rejected: the configuration-sharing
schema exports effective values for every key, which would silently turn inheritance into explicit copies, and the
page would need a per-row "inherited / overridden" state.

## Storage, profiles, sharing

- In the `ui` group, so profiles carry them. Only changed values are saved; a damaged value reads as its default and
  is left in place. Zero is a value (opacity 0 is saved and read as 0).
- `Persist.lua` repairs a non-table in any of the five names.
- Sharing: group `notificationLook` ("Notification appearance") in `setup/TwichConfig.lua`, one table per place,
  built from `NotifyLook.Source(scope)` so defaults and bounds cannot drift. Previews, the page's selection and
  sample data are never saved or shared.
- Profile changes: `Profiles.OnApply("look", "notify-look")` redraws a card that is up and puts previews away.

## Previews

The page has a Show/Hide button per card. They go through `Notify.Preview(kind, nil, { pinned = true })`: the real
renderer, the real coordinator, made-up details.

- Same renderer, same fonts, same look: what is previewed is what a real card will be.
- Works with the card's feature off, and turns nothing on. Reads and writes no game or saved state (no Chronicle read,
  no "seen" marks, no zone state, no friend lookup). Silent unless "Play notification sounds in previews" is on.
- Pinned: stays up (`Notify.PIN_SECONDS`, 10 minutes at most) instead of fading, so it can be watched while editing.
- Editing redraws it **in place** (`Notify.Restyle()` -> each renderer's `restyle`), through one short coalesced
  timer. The entrance is not replayed; the animation group is not touched.
- A real notice always wins: waiting previews are dropped and a showing one that overlaps is dismissed. Combat
  clears previews. Closing the settings, changing profile, or Hide all clears them. One preview per card; showing
  again starts it over, so nothing accumulates, and frames are reused.
- Reduced motion applies to previews exactly as to real cards.

## Runtime

A card is styled each time it is shown (so pooled frames never carry an old font or color), and again, in place, when
the look changes while it is up. Nothing runs per frame and nothing runs while no card is showing. If NotifyLook.lua
failed to load, every card falls back to its own constants (`Arrival.Typeset` and friends).

Fonts: resolved through `MenuStyle.Fonts` (LibSharedMedia, TwichUI's and EllesmereUI's). A missing or undrawable
font is drawn as the card's own and the choice stays; the troubleshooting report lists such fonts. A font registered
later (an addon loading) redraws a card that is up.

## Not verified

Everything above is checked offline with stand-in frames (`tests/test_notify_look.lua`). Not verified in the
game: how a backdrop sits against real text measurements (it is sized from `GetUnboundedStringWidth`), glyph
coverage of a chosen font on non-Western clients, outline appearance, and the EllesmereUI color picker path with
these swatches.

## In-game checklist

1. `/tui` > Notifications > Appearance. With nothing changed, press Show on each of the four cards: each should look
   as it always did (no backdrop). Press Hide.
2. Shared look: change Text size, Title font, Outline and each color while a preview is up. The card should update in
   place without replaying its entrance, and nothing should flash or restart.
3. Raise Backdrop opacity: a panel appears behind the text only; text stays as solid as Text opacity says. Set Text
   opacity to 50: text fades, backdrop and rule do not.
4. Pick a color, then Cancel the picker: the card returns to its previous color. Repeat with EllesmereUI's picker.
5. Choose "Training" in Customize, turn on "Give this card its own look", change its size. The other cards do not
   change. Turn it off: it follows the shared look; on again: its values are back.
6. "Reset this card" asks and names the card; "Reset the shared look" asks and says cards with their own look keep it.
   Confirm neither changed whether a card is on, sounds, or positions.
7. With each card's feature turned off, previews still show and nothing turns on. Previews are silent (sound off).
8. Show a preview, then cause a real notice (walk into a new zone / level up with training / have a friend log in):
   the real one takes its place and the preview goes away.
9. Show a preview and enter combat, close the settings, or switch profile: the preview goes away.
10. Reduced motion on: previews only fade. Try UI scale small and large; large text should not clip.
11. Long names: preview a zone with a long name (e.g. "The Great Sea of Tidal Peaks") by real travel; friend names
    with long BattleTags; long spell names in two columns at 140%.
12. Real notices: each of the four, with a changed look, then reload: look persists. Export a share and import it on
    another character or profile: the look arrives, previews do not.
