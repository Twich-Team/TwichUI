# Food and Drink in EllesmereUI's Unlock Mode

Optional, off until turned on, and only when EllesmereUI is installed. Food and drink options page > **Use
EllesmereUI Unlock Mode**. Code: `modules/FoodDrinkUnlock.lua`, with small hooks in `modules/FoodDrink.lua`.

**Needs checking in the game.** Everything below about EllesmereUI is read from its source
(`../EllesmereUI`, version 9.3.5), and the offline tests use a stand-in that follows it. Nothing here has been seen in
the game.

## What the player gets

- A **TwichUI Food & Drink** anchor in EllesmereUI's Unlock Mode (open it with `/unlock`). It moves the Food and Drink
  buttons as a set; their spacing and layout are not changed.
- Whatever EllesmereUI's Unlock Mode offers a registered element that cannot be resized: dragging, its snapping,
  arrow-key nudging, the X and Y boxes in the cog menu, and anchoring to another element. These are
  EllesmereUI's own; TwichUI draws and implements none of them. There are no width or height boxes, Match Width
  and Height are not offered, and other elements cannot match their size to it (the size is the player's look
  settings, and EllesmereUI drops size matches to an element that cannot be resized:
  `EUI_UnlockMode_Anchors.lua`, `MatchUnusable`).
- Turning it on moves nothing. The place is still saved by TwichUI.
- With the option off, or EllesmereUI missing, or its Unlock Mode missing, Edit Mode moves the buttons exactly as
  before. The choice is kept while EllesmereUI is away; the options page says why it isn't in effect.

## The EllesmereUI interface used (all in the source, nothing private)

| Used | Source |
|---|---|
| `EllesmereUI:RegisterUnlockElements(elements)` | `EUI_UnlockMode.lua:31` (wrapped at `EUI_UnlockMode_Anchors.lua:1585`, `EUI_UnlockMode_Movers.lua:4367`); the same call the suite's own addons make |
| `EllesmereUI.MakeUnlockElement(opts)` and its field list | `EllesmereUI.lua:2428` |
| `RegisterUnlockModeListener(owner, fn(active, closeAction))`, "fire on real session open/close only; combat suspension does not end the session" | `EUI_UnlockMode.lua:59-87` |
| `EllesmereUI.ReapplyOwnAnchor(key)` (optional; applies an existing anchor link after registering) | `EUI_UnlockMode.lua:98` |
| Entry point `/unlock` | `EllesmereUI.lua:3240` |

Element fields given: `key`, `label`, `group`, `order`, `noResize`, `getFrame`, `getSize`, `isHidden`, `savePos`,
`loadPos`, `clearPos`, `applyPos`. Not given: `setWidth`/`setHeight`, `isAnchored`, `noInitHook`, `folder`.

TwichUI hooks `SetPoint` on **its own** anchor frame only. It installs nothing on EllesmereUI or Blizzard frames.

## One anchor, and what it controls

Food and Drink already share one container, so there is one anchor for the set, not two.

EllesmereUI moves a **separate plain frame** (the anchor), sized to the buttons' footprint, never the secure
buttons' parent. The footprint comes from the settings alone (`F.Footprint`): button size, spacing, layout, and how
many of the two buttons are switched on. It is the same with empty bags or before the bags were looked at. The
buttons' parent, which the secure buttons hang from, follows the anchor and is moved by TwichUI, out of combat only.

Why a separate frame: `Frame:SetPoint` is marked `IsProtectedFunction` in the client's API documentation, but the
documentation does not say whether a plain frame that protected buttons are anchored to may be moved in combat.
TwichUI's existing code assumes it may not. EllesmereUI's own combat check tests `IsProtected()` on the frame
itself, which is false for a plain parent, so it could try. With a separate anchor it never touches anything a
protected frame depends on.

If no button is switched on the anchor is hidden from Unlock Mode (`isHidden`); there is nothing to position. With
both on and nothing usable in the bags the buttons are still shown (empty and labelled), so the anchor is
the real, visible footprint; nothing is conjured, no item or secure action is changed for it, and no preview
state is saved.

## Position ownership

| What | Owner |
|---|---|
| The place (`TwichUIDB.ui.foodDrinkPosition = { x, y }`, the centre's offset from the screen centre, in screen units) | **TwichUI**. The one record Edit Mode also writes. Nothing else is stored. |
| Anchor links ("anchor to another element") | **EllesmereUI**, in its own saved data. TwichUI neither reads nor writes them. |
| Where the buttons are now | The anchor, while the option is on and the buttons are on; else the saved place. |

- `loadPos` returns the saved place, or the default, as `CENTER`/`CENTER` offsets. EllesmereUI saves every
  element as `CENTER`/`CENTER` offsets in screen units, which is this record's own convention, so `savePos` stores them
  as they are. Scale is converted once, from the anchor's own scale to the screen's (`U.OffsetFrom`); it
  is never applied a second time.
- Save & Exit calls `savePos` for what was moved. A discard calls it with the open-time place and applies it. Neither
  writes when the place is unchanged, so a place that was never set stays unset.
- Repeated sessions do not drift: EllesmereUI's pixel snap is idempotent, and the record is only rewritten from
  what was moved. The first apply after a reload may land up to half a physical pixel from where Edit Mode put the
  buttons, because EllesmereUI aligns what it places to its pixel grid.
- While the option is on, **Edit Mode's outline is not shown** (one mover only). Its right-click reset is replaced by
  the options page's **Position > Reset**, which clears only this record and puts the anchor and the buttons back to the
  default place. An anchor link made in Unlock Mode is removed in Unlock Mode.

### What EllesmereUI keeps of it

EllesmereUI's spec and layout system saves **a copy** of each registered element's `loadPos` into its own
layouts and re-applies it through `savePos` when a layout, profile or spec changes (`EllesmereUI_SpecOverrides.lua`
`HarvestLayer` and its apply). TwichUI's record stays the one that is read, but with the option on, an EllesmereUI
profile or spec switch can put back a place it banked earlier. This is how EllesmereUI treats every element;
there is no way to opt one out. Such a `savePos` is ignored while the option is off or the buttons are off, so
turning the option off ends it.

### EllesmereUI absent or the option off

The buttons are placed from the saved place and moved in Edit Mode. If they had an anchor link, they sit at the last
place that was saved (a saved place is written when an anchored element's session is saved), and the link is
EllesmereUI's again when it returns.

## Combat

- Unlock Mode cannot be opened in combat, and suspends itself when combat starts (`EUI_UnlockMode.lua:778`,
  `EUI_UnlockMode_Session.lua:1897`); nothing can be dragged then.
- The buttons' parent, size and attributes are not touched in combat. If the anchor moves anyway (a layout applied at a
  combat reload, an anchor following its target), `F.Reposition` records only that a move is waiting
  (`moveWaiting`, reason code `unlock-deferred-combat`) and, when combat ends, places the parent where the anchor
  is **then**. No value is queued, so the latest is the only one.
- A move waiting is dropped when the option is turned off or the buttons are turned off, and the place used is
  then the saved one.
- Button attributes are set by `Fill` as before and are not read or changed by this feature.

## Lifecycle

- Registered once per session, at `ADDON_LOADED` for EllesmereUI, `PLAYER_LOGIN`, or `PLAYER_ENTERING_WORLD`,
  whichever finds EllesmereUI and the option; and when the option is turned on. It is **never unregistered**:
  `UnregisterUnlockElement` deletes the player's anchor and size-match links for the key
  (`EUI_UnlockMode_Anchors.lua:527`, `PruneStaleLinks`). The anchor is hidden (`isHidden`) while the buttons are off.
  (If the option is off for a whole session, nothing is registered, and EllesmereUI drops the links with this key
  the next time Unlock Mode opens: `ValidateStoredLinks`, `EUI_UnlockMode_Anchors.lua:611`.)
- A failed registration is counted (`unlock-register-failed`), reported in `/tui diagnostics`, and not retried.
- The listener only records that a session is open (so a saved layout is not applied over a drag) and follows the
  anchor once more when it closes. No overlay, tooltip or preview of ours exists.
- Not per frame: the anchor's `SetPoint` is hooked (two `GetCenter` calls and, out of combat, one `SetPoint`), and
  EllesmereUI's own callbacks do the rest.

## Reason codes (counts only)

`unlock-deferred-combat`, `unlock-save-ignored` (a layout save while the option or buttons are off),
`unlock-save-refused` (not `CENTER`/`CENTER`, or not a usable number), `unlock-register-failed`.
`/tui diagnostics` > Food and water buttons also shows: the option, the status (`off`, `no-eui`, `no-api`,
`waiting`, `register-failed`, `module-off`, `active`), whether the anchor is in charge, whether a session is open, and
whether a move is waiting.

## Checked offline, and what is not

`tests/test_food_drink_unlock.lua` covers: registration once and never unregistered; the label and fields; the
anchor's size for each layout and button count and with empty bags; following a drag; Save & Exit, a discard, and six
sessions without drift; scale conversion; combat (parent not moved, only the latest place applied after, cancelled
by turning the option or buttons off); a layout applied through EllesmereUI; refused and ignored saves; reset scoped to
the one record; one mover; EllesmereUI missing, late, without the mover API, and failing; and the diagnostics' codes.
The stand-in follows EllesmereUI's documented contract; it is not EllesmereUI.

## Manual checklist (in the game)

1. **TwichUI alone** (EllesmereUI disabled): Edit Mode moves the buttons and right-click resets them as before.
2. **Enable the option** with EllesmereUI on, without changing the place. *Expect:* the buttons do not move.
   `/tui diagnostics` says status `active`.
3. **`/unlock`**. *Expect:* a mover labelled "TwichUI Food & Drink" over the buttons, the size of the set.
4. **Drag it**, and use the arrow keys, snapping and the X and Y boxes. *Expect:* the buttons follow; no
   size boxes; Match Width/Height not offered.
5. **Save & Exit, then click the buttons.** *Expect:* they eat or drink as before. Cancel instead: they go back.
6. **`/reload`.** *Expect:* the same place, within half a pixel.
7. **Open and save Unlock Mode five times** without moving. *Expect:* no drift, one mover.
8. **One button, then both** (options), and **vertical** layout. *Expect:* the mover resizes to match.
9. **Empty bags.** *Expect:* the mover and the two empty buttons are still there.
10. **Other UI scales**, and a different layout. *Expect:* the mover and buttons agree.
11. **Profile or spec switch** in EllesmereUI. *Expect:* the place may change to what EllesmereUI banked; no
    duplicate mover.
12. **Turn the buttons off, then on.** *Expect:* the mover goes and returns; anchor links survive.
13. **Combat.** `/unlock` in combat is refused by EllesmereUI. Start combat with Unlock Mode open: it suspends.
    Reload in combat with an anchor link: the buttons move when combat ends. No "action blocked" message.
14. **Disable EllesmereUI** and log in. *Expect:* Edit Mode works, the choice is still ticked, the page says why.
15. **Position > Reset.** *Expect:* the buttons and the mover go to the default place; nothing else moves.
16. **Item choice and clicks** are the same with the option on and off.
