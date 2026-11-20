# Class Portrait Decorations

Opt-in player portrait artwork for TwichUI V2. Open `/tui options`, then
**Class Portrait Decorations** under Other addons. Home's appearance catalog also
links here. The feature works without opening Settings. It never attaches to a
Blizzard, target, focus, party, raid or pet frame.

## Verified integration and limits

Source reviewed: [EllesmereUI 9.9.1, commit 8abfcbf](https://github.com/EllesmereGaming/EllesmereUI/tree/8abfcbf6afa4129369cdc9fb5e03e96d1fdd94e5/EllesmereUIUnitFrames).
This is a source-verified adapter for that structure, not a public API contract or
an assertion that all EllesmereUI versions work.

- `EUI_UnitFrames_Init.lua`, `InitializeFrames`: spawns the named
  `EllesmereUIUnitFrames_Player` only for the EllesmereUI player-frame source.
- `EUI_UnitFrames_Engine.lua`, `SpawnUnitFrame`: secure unit button. Detection
  accepts only the exact named frame with readable `unit == "player"`.
- `EUI_UnitFrames_Portrait.lua`, `CreatePortrait`: `frame.Portrait.backdrop` is a
  direct child of that player frame. It contains the portrait background and
  2D/3D/class art. `SwapPortraitMode` reuses the backdrop when replacing the
  active portrait element. The backdrop is the visible portrait rectangle,
  including its own shape treatment; it is not a guessed health-bar rectangle.
- `EUI_UnitFrames_Layout.lua`, `UpdateBordersForScale`, and
  `EUI_UnitFrames_Reload.lua`: portrait size/shape/layout updates reuse this
  backdrop. Anchors carry movement, and inherited effective scale carries frame
  and UI scaling without a separate multiplier.
- No stable public unit-frame layout callback was found. `_EUF_ReloadFrames`
  merely arms a next-frame throttle; internal callers also use namespace
  references. Hooking that global would not reliably observe completed layouts,
  so this implementation does not hook it.

Detection runs at login, relevant addon loads, entering the world, display/UI
scale changes, combat end, profile application and settings changes. Four bounded
startup/load retries (0, 0.5, 2, 5 seconds) cover creation after event delivery.
Only the verified player frame and backdrop get size/show/hide script hooks and
secure post-hooks on their strata and frame-level setters, once per reference. There is no
OnUpdate, hierarchy enumeration, global layout hook or recurring timer. Hooks
remain inert while off. One reusable holder/texture is reparented only outside
combat; missing/incompatible references hide the texture. Recreated references
are checked on each relevant event/hook; recreation that emits none of these
signals after the startup window waits for the next event or opening Settings.
Unknown structures fail closed. No EllesmereUI saved data is read or changed.

The holder is mouse-disabled and parented to the portrait backdrop. By default it is placed one
frame level behind the player frame within its strata. The new **Draw above unit frame**
setting raises it 20 levels above the higher of the player frame and portrait,
clearing the verified text host. **Frame strata** defaults to Follow unit frame;
Low, Medium, High and Dialog override it. Strata takes priority over frame levels.
Both choices persist per profile, participate in configuration sharing, and defer
until combat ends. Reset to Automatic keeps these layering preferences; Reset
this page restores them. Above mode may cover bars/text but never captures clicks.
With the defaults, portrait backgrounds,
models, health/resource bars and text therefore paint over it. Hidden portraits
stay hidden, including during preview. Foreground overlap and another addon's
native ornament may obscure this decoration; TwichUI does not hide native art.

Forever reference: `wow-ui-source` branch `forever`,
`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`, client 1.60.1.70938.
`SimpleTextureBaseAPIDocumentation.lua` verifies `SetTexture`'s success result;
`SimpleFrameAPIDocumentation.lua` documents frame scaling/parent APIs. Existing
TwichUI target artwork and Forever unit-frame source establish the event and
visual-child patterns. No protected attributes, click handlers or external layout
methods are changed. All decoration layout/reparent/create operations wait until
combat ends; an existing attachment remains drawn, while stale artwork is hidden.
This design and mock coverage do not establish absence of client taint.

## Artwork and fit

All nine original 1254×1254 RGBA PNGs and the supplied README are preserved byte
for byte in `assets/class-portrait-source/`, excluded by `.pkgmeta`. Runtime assets
are nine predictably named `media/classportrait/<CLASS_TOKEN>.tga` files, about
9 MiB total. They use the project's established uncompressed true-color TGA
format: power-of-two 512×512, 32 bits per pixel, eight alpha bits, bottom-left
origin, no lossy compression, no upscaling. Renderer acceptance remains a client
check; this does not assert a maximum texture size or support for arbitrary PNGs.

Rebuild with `python3 tools/make_class_portrait_art.py` (standard library only).
It reuses TwichUI's PNG reader and premultiplied-alpha area filter, keeping the
whole canvas and its proportions. Faint alpha at or below 8 is cleared by the
existing reader for runtime processing; source bytes remain unchanged. Every
class's clear opening is measured independently along its two interior midlines
and recorded in generated `classportrait/Art.lua`. These are straight inner edges,
not the outer ornament bounds or rounded corners. Shaman's opening is narrower.

For opening width/height `ow, oh` and portrait width/height `pw, ph`, the uniform
factor is `max(pw / ow, ph / oh)`. This contains the full portrait inside the
opening for nonsquare rectangles, leaving some clearance on the other axis.
The texture centre is offset so the measured opening centre equals the portrait
centre. Size Adjustment multiplies this factor, keeping that centre fixed.
Offsets are then added in portrait-local units. Texture and anchor use the same
parent scale; no effective-scale ratio or SetScale is applied a second time.
At very small sizes the 512px art is filtered by the client. Rounded-corner fit,
native borders and elaborate portrait shapes require visual acceptance.

Automatic Fit off uses a fixed 52-unit starting opening; it still follows the
portrait's centre, movement, visibility and inherited scale. The intended artwork
composition is a square left-side portrait, with the ridge extending right above
the bars. Other portrait positions/shapes may be less suitable aesthetically.

## Settings and persistence

The existing profile-owned `TwichUIDB.ui.classPortrait` stores `enabled` (default
false), `automatic` (true), `size` (100; 50–150%), `x` and `y` (0; −100–100), `above` (false), and `strata` (inherit).
Getters validate values without erasing invalid input; setters reject invalid
values. Defaults are lazy; no schema migration or separate database is needed.
Reset to Automatic restores automatic fit, size and offsets, preserving enabled.
Preview uses only the player's class, can run while disabled, and ends on settings
close, combat start or profile change. It cannot force a hidden frame visible.
Unsupported classes remain inactive; texture-load refusal reports a useful status.
Class is read once after login, including when the feature is disabled.

Diagnostics exposes retained-frame and listener gauges. The work is event-rare
and bounded, so no timed performance scope was added.

## Verification and in-game acceptance

Unit coverage: nine runtime class selections, unsupported class, disabled default,
missing/delayed/recreated frames, containment and centre alignment for every asset,
relative manual offsets, profile storage/restoration and invalid values, reset,
resize inheritance, combat deferral/stale hiding, single texture reuse, preview
cleanup and missing textures. Asset checks rebuild all TGAs/metadata, verify
alpha/header/dimensions and source/runtime packaging boundaries. Settings tests
cover the new controls, search catalog, navigation, reset contract and icon.
The focused `feature class-portrait --profile cloud` selects these tests plus
Settings/core/shared UI dependencies, simulator smoke and this Settings page.

Simulator screenshots are structural settings evidence only: the actual
EllesmereUI layout is not installed in the lab, and the cloud profile omits game
art. No real-client visual alignment, combat, input, taint or reload verification
has been performed. No generated screenshot is represented as an in-game capture.

Before accepting the draft PR in WoW Forever:

1. Install the branch alongside EllesmereUI's unit frames. Log in and confirm the
   new feature is off. Open `/tui options`, select Class Portrait Decorations and
   enable it with a square portrait on the player's left.
2. Confirm the class matches your character. At 100%, inspect all four opening
   edges and rounded corners; the ornament should wrap left, with its ridge above
   the bars. Check health, resources, names, portrait, clicks and tooltips remain
   visible and usable. Repeat on the other eight supported classes as available.
3. Move the player frame; resize portrait/frame and change frame scale and UI
   scale (for example 75%, 100%, 125%). Check fit stays centred. Try a nonsquare,
   detached and hidden portrait; hidden portraits must leave no floating art.
4. Change size and both offsets, move the frame again, then use Reset to
   Automatic. Check offsets remain relative and reset retains enabled state.
5. Toggle Preview while disabled, then close Settings and enter combat. Preview
   must end. With enabled art already attached, enter combat: it must remain.
   Change settings in combat and confirm they apply on leaving combat, with no
   blocked-action or taint errors. Check player targeting/menu/tooltip behavior.
6. Switch EllesmereUI and TwichUI profiles; switch 2D/3D/class portrait modes;
   hide/show the frame. Confirm correct visibility, positioning and recovery.
7. Reload/relog with nondefault offsets and confirm persistence. Disable
   EllesmereUI, reload, and enable this feature: status must say player frame not
   detected with no artwork. Re-enable EllesmereUI and reload to verify recovery.
8. Inspect against light/dark world backgrounds, and confirm target/focus/pet/
   party/raid frames never receive this artwork. Record client/EllesmereUI
   versions, portrait style and screenshots for any alignment discrepancy.

Layering acceptance: toggle Draw above unit frame, compare Follow unit frame and
High strata, check text/bar overlap and click-through, change layers in combat,
and confirm profile switches/reloads retain them. Real-client layering remains
an acceptance check.
