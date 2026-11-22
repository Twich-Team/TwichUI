# UX02 — shared artwork picker design and foundation

**Proposed design for owner review; no extraction or rule schema change is implemented.**
Baseline: `main` at `c7f8741` (2026-11-22). This document closes the authorized
Batch 5 discovery work. It does not authorize the next implementation batch.
The Reminders picker is the approved visual/interaction reference, not a redesign
candidate. See the [artwork inventory](shared-artwork-inventory.md),
[consumer specifications](shared-artwork-rule-integrations.md), and
[existing artwork pipeline](../reminders-art.md).

## Audit: reuse the chooser, keep each feature's meaning

| Existing source | Reusable part | Reminders-specific part to retain in an adapter |
| --- | --- | --- |
| [`reminders/Gallery.lua`](../../!!!TwichUI/reminders/Gallery.lua) | Lazy catalog, identity lookup, categories/counts, plain-text search, stable ranking and candidate equality | Source/display mode inference, `CandidateOf`, `SetUIMode`, and especially `Choose` → `RM.SetDisplayMany` |
| [`reminders/Config.lua`](../../!!!TwichUI/reminders/Config.lua) | Four legacy art records, generated gallery texture metadata, aspect/crop and small-file resolution | `display` schema/defaults, mode validation, allowed Reminder icon set and atomic setters |
| [`RemindersImagePicker.lua`](../../TwichUI_Settings/pages/RemindersImagePicker.lua) | Category sidebar, source tabs, search, tiles, hover/selection skins, preview/details strip, item input, Apply/Cancel and staged candidate | `session.id`, `RM.Get`, direct `G.Choose`, reminder-specific copy, `RemindersEditor.ItemInfo`/Kit presentation, `RemindersPage.QueueRefresh`, preview/catalog/designer coordination |
| [`RemindersPreview.lua`](../../TwichUI_Settings/pages/RemindersPreview.lua) | `Place`/`RestoreAnchor`: current docking, scale/height fitting and conditional restoration of an anchor shifted by the companion | Reminder live-preview rendering, display state and callbacks |
| [`Reminders.lua`](../../TwichUI_Settings/pages/Reminders.lua), [`Window.lua`](../../TwichUI_Settings/Window.lua) | Existing page-hide/settings-close and special-frame Esc routing patterns | Reminder selection identity, live-preview restoration and designer refusal |

The current catalog is **79 entries**: 67 generated art records + four earlier
artworks + eight registered icons. The “80 entries” sentence in `reminders.md`
is stale; source and the manifest establish the count. Catalog identity and saved
target are different for an icon: UI key `icon-mage` maps to saved icon `mage`.
Never save the UI key as a registry ID or rename the `shield`/`ammo`/`wellfed`/
`enchant` and `reminder-*` art IDs.

Current search takes up to eight whitespace-separated words, ignores case,
requires every word in name/category/keywords, and ranks all-name matches first,
then catalog order. The search input has a 60-character limit. Preserve this,
the six categories plus All, the two artwork/game-icon sources, the three-column
grid, thumbnails, details preview, item ID/link/drop entry, scroll-to-current,
Apply and Cancel. Preserve actual code geometry and fit behavior: for example,
current constants are 512×668, 96-unit tiles and 78-unit thumbnail bounds; prose
claiming all thumbnails are 64 units is not an instruction to resize them.
Do not normalize legacy crops or regenerate artwork during extraction.

## Smallest proposed architecture

1. **Core `R.Artwork`**, proposed `!!!TwichUI/artwork/Catalog.lua`: lift only
   catalog/search, ref checks and texture resolution/drawing. Read the existing
   generated `R.ReminderArtData` unchanged; keep the current generator and manifest
   as provenance. Move immutable legacy crop/size metadata here, leaving
   `RM.Art`, `RM.ArtTexture` and Gallery catalog wrappers compatible. Reuse
   `R.Icons.Get/Apply` for registered icons, not copied file/crop/tint tables.
   No frame, events, persistence, feature loading or consumer registry here.
2. **Settings-only `R.SettingsArtworkPicker`**, proposed
   `TwichUI_Settings/ArtworkPicker.lua`: adapt the existing frame in place;
   replace reminder storage calls with one caller acceptance callback. Keep one
   lazily built frame and the existing bounded, reused tile pool. This is one
   chooser, not one per consumer. Move the small item-input/details helpers out
   of their Reminder editor dependency while preserving their behavior. Reuse
   SettingsWidgets/Material and the existing companion placement math. If needed,
   lift only `Place`/`RestoreAnchor` into two Material helpers and delegate the
   existing Preview wrappers to them; do not build a new window/overlay manager.
3. **Thin Reminders adapter** in the existing `RemindersImagePicker.lua`: retain
   its public entry points for the page and tests. Translate between shared refs
   and existing Gallery candidates, then call `G.Choose` on Apply. Keep display
   mode changes, text-only → image behavior and `RM.SetDisplayMany` atomicity.
   Its owner checks keep the current designer refusal, hide templates/live
   preview before opening, and restore preview only while its page is current
   and the companion place is free. The shared chooser never invokes those
   Reminder objects itself.

Load core metadata after `Icons.lua`/`reminders/ArtData.lua` and before Reminder
Config/Gallery; it must work when Reminders is disabled. Load Settings UI after
Widgets/Material and before the Settings window becomes callable. Current page
files register earlier in the Settings TOC, so adapter wrappers must resolve the
shared service when called, not capture a not-yet-loaded singleton at file load.
No new addon, provider/plugin registry, filesystem scanner or generic editor
framework is proposed. Load-order edits require manifest/opt-in checks later.

## Exact proposed reusable contract

The following names and semantics are the reviewable contract, **not existing APIs**.
Consumers own their validation, data format, undo behavior and persistence.

### References and core operations

A `Ref` is a fresh plain table containing only `kind` and `id`:

- `{kind="art", id="reminder-health-potion"}`: stable artwork ID. New IDs use
  1–40 ASCII lower-case letters/digits/hyphens; existing shipped IDs stay intact.
- `{kind="icon", id="auctionHouse"}`: exact-case registry key, 1–64 ASCII
  letters/digits/underscore/hyphen. Never lower-case it or store a file path.
- `{kind="item", id=6948}`: finite integer 1–2147483647; the existing Reminder
  item bound, without depending on Workshop. This is a picture choice only.
- `{kind="automatic"}`: UI-only staged reset, with no `id`. Rule persistence
  represents it by the **absence** of an override. `nil` at Open means no custom
  selection; if automatic is enabled it starts on this automatic candidate.

| Operation | Exact result / ownership |
| --- | --- |
| `R.Artwork.Check(ref)` | Fresh canonical ref or `nil, "invalid_ref"`. Structural check only; unknown but well-formed IDs survive. Unknown kinds, links/paths, control characters, oversized/nonfinite/fractional values and nested data are rejected; extra scalar metadata is not retained. `automatic` is accepted only as a UI value. |
| `Categories()` | Fresh ordered category-name array: All plus the existing six. No caller mutates shared catalog tables. |
| `Search(query, category)` | Fresh ordered array of read-only entries `{key, ref, name, category, description, keywords, related}`. Entry metadata remains catalog-owned; refs passed to callers are copied. `nil` category means All; unknown category returns empty; nonstring query means empty. Search semantics are the current Gallery semantics above. |
| `Get(ref)` | Read-only catalog entry or `nil`; game item refs and automatic are not catalog entries. Neither absence nor unknown ID is a save instruction. |
| `Draw(texture, ref, size)` | `true, "ready"` after setting the actual art/icon/item texture, crop, aspect, tint and alpha. Otherwise clear the texture and return `false, reason` (`automatic`, `loading`, `unavailable`, `invalid_ref`, `invalid_size`); caller paints its automatic fallback and status. Do not let `R.Icons`' emblem fallback masquerade as a successfully resolved custom icon. Positive finite size required. Art/icon refs require both curated catalog membership and a usable target; a registry-only ID is unavailable. No saved write or polling. |

Keep current per-source rendering: Reminder artwork uses its existing 64-unit
small-file threshold/crop/aspect; `R.Icons` keeps its current 26-unit threshold,
coordinates and tint. New unregistered art gets an explicit metadata mapping to
existing files, with 32px variants at <=26 UI units and 64px above, without a
new crop. Item icons keep the Reminder picker's existing square inset. Consumer-specific
portrait masks are outside `Draw`: Magic Inventory must apply/remove its mask
after every custom/automatic render, as specified for its identity surfaces.
Missing art/icon entries
are unavailable; missing item metadata is loading/unavailable as established by
the existing item-info helper. A valid item ID remains selectable even while its
name/icon is pending, as today; metadata readiness must not invent an item or
change its ID. Refresh from the existing item-data readiness path, no timer loop.

### Chooser operations

```lua
local ok, tokenOrReason = R.SettingsArtworkPicker.Open(ownerFrame, {
    key = editorIdentity,             -- opaque caller identity; not SavedVariables
    selection = existingRefOrNil,    -- copied; never modified by the chooser
    IsCurrent = function() ... end,  -- owner/profile/editor generation + existence
    automatic = {                    -- omit to keep Reminders' current footer
        label = "Use automatic icon",
        name = "Need (automatic)",
        Draw = function(texture, size) ... end, -- caller's existing automatic painter
    },
    OnApply = function(ref) ... end,  -- return true, or false, playerFacingReason
    OnClosed = function(reason) ... end,
})
R.SettingsArtworkPicker.Close(ownerFrame) -- true if its session was cancelled; else false
R.SettingsArtworkPicker.Apply(ownerFrame) -- true if accepted; else false, reason
R.SettingsArtworkPicker.State(ownerFrame) -- copied snapshot below, or nil for another/no owner
R.SettingsArtworkPicker.Shown()          -- boolean
R.SettingsArtworkPicker.Frame()          -- frame or nil; inspection/placement only
```

`Open` returns `true, token` after validating owner/options/currentness. Invalid
requests return `false, "invalid_owner" | "invalid_options" | "invalid_ref" |
"stale_owner"` without disturbing an existing valid session. A repeated request
with the same owner/key cancels it (the existing Reminder toggle behavior) and
returns `false, "toggled"`; a valid different owner/key cancels the old session
with reason `replaced`, then opens a fresh one. Tokens are session-local identity,
not frame handles, save values or callbacks consumers may replay. `Apply(owner)`
uses exactly the same checked path as the Apply button; wrong/no owner returns
`false, "not_open"`, invalidated owner `false, "stale_owner"`, and callback
rejection `false, "refused"` with its message shown in the picker. `State(owner)`
returns `{key, candidate, source, category, query}` with copied candidate data;
`source` is `"art"` or `"game"`. It is read-only inspection, never a save value.
`Frame()` never builds a frame. The Reminder adapter preserves `Open`, `Cancel`,
`Apply`, `Shown`, `Frame`, `ReminderId` and `Candidate` behavior/legacy candidate
shape using owner-scoped state; it must not report a Loot/Inventory session as
an open Reminder picker. Keep source/drawing compatibility where used by the
existing editor and simulator as well.

Browse/filter/tile selection and preview only change the local candidate.
**Use automatic icon** is a small secondary control in the available left footer
space; selecting it stages the automatic candidate and preview, then **Apply**
confirms. Keep the existing Apply/Cancel positions/styles. Reminders omits this
option initially, keeping its current footer and defaults unchanged.

Apply first rechecks `IsCurrent()` and owner visibility, then validates and copies
the candidate. Known catalog choices must still resolve; unavailable saved art
stays visible as unavailable but cannot be newly applied until replaced/restored.
Syntactically valid pending item IDs retain today's Apply behavior. Call
`OnApply(copy)` exactly once per attempt, blocking double-click/reentrant Apply.
`true` means the consumer has accepted it under its normal save model; close
with reason `applied`. `false, message` keeps the picker and candidate open and
shows that plain message. A callback error stays open with a generic refusal and
the existing fault-reporting path; never retry or partially save on its behalf.
Do not expose catalog metadata or arbitrary paths to `OnApply`. Recheck the
session token before post-Apply cleanup: a setter/event that closes or replaces
the owner must never hide a newer session or emit a second OnClosed.

### Cancellation and lifecycle rules

| Trigger | Required result |
| --- | --- |
| Cancel, X, Esc, raw frame hide | Cancel candidate; no OnApply. Esc in an active text input first retains the existing clear-focus behavior; Settings' normal Esc routing then closes the picker before its parent. Never register a game-menu Esc handler. |
| Switch Settings page, rule/reminder selection, editor deletion, profile apply/reset/copy, or same-rule edits affecting automatic art/label (Loot action; MI included item/category/kind) | Cancel/invalidate the bound session. Recheck generation at Apply so a late callback cannot target a replacement rule/profile with the same numeric ID/name. |
| Settings close or owner hidden | Close only the picker state. Never reset the caller's editor draft. MI retains its existing applied-but-unsaved draft across page hide; Loot already commits on picker Apply. |
| Reopen | Start from caller's present saved/draft selection, clear search and item-entry fields, All category, matching source tab, scroll-to-current. Discard previous candidate/filter state. |
| Any close | Clear focus, candidate/callback/owner references and pending metadata session work. Call OnClosed exactly once with `applied`, `cancelled`, `replaced`, `owner_hidden`, `settings_closed` or `invalidated`. No OnApply/save from cleanup. |

`IsCurrent` and OnClosed must not save or open other companions reentrantly.
Callers close the picker before replacing an editor/profile and use current-page
refresh to restore preview only when appropriate. Install owner-hide hooks once,
not once per open; retained hooks consult the current session rather than retain
old callbacks. Reuse the existing Settings close callback and special-frame
priority. The chooser itself knows no Reminder ID, rule ID, roll action,
destination, profile store or validation policy beyond the reference shape.

## Reminders compatibility and future catalog additions

Translate shared `art/id` to existing `kind="art", target=id`; `icon/id` to
`kind="icon", target=id`; `item/id` to `kind="item", item=id`, and back without
renaming stored values. Preserve legacy modes, text/color/size and one atomic
`G.Choose` notification. Existing unavailable Reminder values remain owned by
Reminder validation; do not rewrite them through a stricter new cleaner on Open
or Cancel. If a legacy value cannot be represented, open with no candidate and
the existing unavailable description; no implicit reset or save.

First prove parity against the existing 79-entry baseline. After owner approval,
add only approved inventory rows to the **same** catalog (not a second picker).
Registered icons need inclusion in Reminders' curated allowed icon set before
Reminder Apply can accept them; do not whitelist the entire registry. New art
records must also resolve through the compatible `RM.Art`/`ArtTexture` wrappers.
Existing generator assets, IDs and recorded selections are preserved; additive
hand-maintained mappings for already bundled assets stay separate from generated
ArtData output and never claim to be generated gallery crops. Preserve baseline
relative order; add approved rows at the end of their existing category.

## Implementation sequence and focused verification

1. **Review this contract and curated list.** Decide the proposed `rule.artwork`
   shape/compatibility policy and automatic control placement. No runtime/schema
   work is Ready before that review; [mini-specs](../autonomous-ready-tasks.md#ux02-specified-follow-ups-awaiting-owner-review)
   make the boundaries reviewable.
2. **Shared extraction with Reminders parity**, then approved catalog mappings,
   in separate logical commits. Keep consumer rules untouched. Test Gallery
   search/order/refs/legacy rendering and reminder atomic Apply/Cancel using
   `tests/test_reminder_gallery.lua` and `tests/test_reminders_settings.lua`.
   Add cases for owner replacement, same-owner toggle, source switching,
   unavailable/current/pending refs, failure/reentrant acceptance, every close
   reason, profile generations and no callback leaks/frame growth. Verify TOCs,
   Reminders disabled and Settings load-on-demand. Validate approved file paths
   and duplicate targets without rebuilding unrelated art.
3. **Loot Rules consumer**, following its immediate-save model; then **Magic
   Inventory consumer**, following its private draft/Save model. Keep separate
   commits/PR slices so either can be deferred. Their exact surfaces, sanitizer,
   duplication, profile/backup and behavior-invariance checks are in the
   [consumer specification](shared-artwork-rule-integrations.md).
4. **Useful visual checkpoint only:** selected existing Reminders picker poses
   (`picker`, `pickerSearch`, `pickerGameApply`, `pickerNarrow`, `pickerRender`)
   plus the affected rule-editor poses after those exist. Compare to the current
   picker reference at normal/narrow/scaled sizes and 20/24/32/48px icon uses;
   retain action labels and mask cleanup. Simulator evidence is structural,
   not native appearance/input acceptance. No full simulator/release suite is
   warranted for this design-only batch.

Current work is **source-inspected/documentation-verified**, with a bounded
offline artwork shortlist review; it implements none of the proposed APIs.
Verification here is local links/paths/IDs, count/provenance consistency and
`git diff --check`. No addon behavior, simulator or real-client claims. No new
runtime diagnostics are added. Future bounded static searches/tile reuse need
no background instrumentation; use existing Settings scopes and measure a
specific gap if one appears, rather than create broad monitoring infrastructure.
