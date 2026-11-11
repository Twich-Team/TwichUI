# TwichUI settings design system

The approved targets are [Settings/Home](reminders-revision/SETTINGS_HOME.png),
[Reminders and preview](reminders-revision/REMINDERS_PREVIEW.PNG),
[When](reminders-revision/REMINDERS_WHEN_BUILDER.png) and
[templates](reminders-revision/REMINDERS_TEMPLATE_CATALOG.jpeg).
The completed Reminders implementation is the practical reference. Its private drafts, placement transaction,
preview visibility and condition behavior remain feature-owned. This rollout changes settings presentation only.

## Materials and hierarchy

| Role | Treatment | Runtime source |
|---|---|---|
| Outer window | Neutral espresso; narrow sculpted bronze corners and edges | `media/style-v2/craft/frame.tga`, `SettingsCraft.Frame` |
| Header / footer | Quiet walnut leather; warm ivory branding | `media/reminders/materials/{face,grain}-header.tga` |
| Ordinary section / feature card | Canonical Reminders walnut; shallow recessed bronze rim | `SettingsWidgets.Panel(frame)` → `PanelFace(frame, "walnut")` |
| Raised card | Restrained chestnut; brighter upper edge; quiet bronze rim | `PanelFace(frame, "card")` |
| Preview / well | Deep espresso; no decorative wash over the content | `PanelFace(frame, "canvas")` |
| Input | Recessed field; painted focus / disabled states | `media/style-v2/craft/field*.tga` |
| Selection | Dimensional leather and aged gold, with a visible relief outline | `selection.tga`, `selection-hot.tga` |
| Primary action | Antique gold; reserved for an explicit confirmation | `primary*.tga` |
| Destructive action | Muted rust and bronze, alongside its scope / confirmation | `danger*.tga` |

All paths above are relative to `!!!TwichUI/`. `Material.FILE`, `Material.LEVEL` and `Look.pal` own shared material
and semantic roles. Large areas use the quiet materials; no new page-specific tint or grain family is needed.
`Material.PanelFace` adds a hollow rim over a face and three non-overlapping leather strips. `Craft.Sheet` makes nine
textures with independent source cuts and fixed UI corners. Stretch edges along their length; do not stretch a whole
button or reference screenshot. Ordinary UI text is always native text, never embedded in a painting.

## Reusable components

| Component | API and ownership |
|---|---|
| Main settings shell | `Material.CalibrateSettings(window, true)`; `FrameLook.Shell` retains geometry and input |
| Companion shell | `Material.WorkspaceFrame(frame)`; feature owns its lifecycle |
| Card / inset | `Material.PanelFace(frame, "card" / "editor" / "canvas" / "espresso")` |
| Shared panel / well | `SettingsWidgets.Panel(frame)` / `.Well(frame)`; returns textures callers may hide |
| Buttons | `SettingsWidgets.Button(parent, label, width, kind, callback)` |
| Explicit confirmation | `SettingsCraft.Control(button, "confirmation")`; refines an existing button without extra hooks |
| Destructive action | `SettingsWidgets.Button(..., "danger", callback)` |
| Navigation selection | `Material.NavItem(button)`; `.sel:SetShown`, `.hover:SetAlpha` |
| Reminder / context selection | `Material.ReminderRow(row)` and `Material.MenuStyle(menu, true)` |
| Tabs / segments | `Material.Segment(parent, label, width, callback)`; `:SetSelected(boolean)` |
| Switch | `SettingsWidgets.Checkbox(parent, callback)` uses `Material.Pill`; `SetChecked`, `SetActive`, `SetHot` |
| Dropdown / context menu | `SettingsWidgets.Dropdown`; existing bounded shared menu, keyboard / close behavior |
| Numeric slider | `SettingsWidgets.Slider`; typed value, bounds, disabled behavior and native slider remain authoritative |
| Edit field | `SettingsWidgets.EditBox`; native focus and Enter / Escape preserved |
| Scrollbar | `Material.ScrollRail(scroll)`; native range / hit regions, painted track and thumb |
| Chips | Existing `SettingsCraft.Control(button, "chip")` |
| Disclosure | Page-specific secondary sections in `SettingsDesign`; `Show` / `Hide` segments; session state only |
| Help / tooltip | `Interact.Tip` for full help; `Material.ContextTip` for reference companions |
| Dialog / modal | Existing `Interact.Confirm` and feature windows; scope, cancellation and combat rules remain intact |
| Status | Existing text labels plus `Look.pal` semantic colors; never replace status words with color alone |

`TwichUI_Settings/Design.lua` adapts the settings-local widget table. It leaves core `Look`, gameplay overlays,
SavedVariables and feature setters alone. Completed reference pages (`designReference`) continue to choose their own
controls explicitly. New pages automatically join the shared shell and widget family through `Kit.Page`.
Do not import Reminders behavior into shared presentation code.

`SettingsWidgets.Tab` also uses the shared segment family for hosted rule steps and guild-bank views. For dense tables,
the checkbox adapter retains an explicitly resized hit region: below 26 units wide it shows a recessed square and native
checkmark rather than compressing a pill. Both variants expose the same checked, active and hot API. Place labels relative
to the control's actual right edge; do not assume the former checkbox width.

## Type, spacing and feedback

Use `SettingsWidgets.Text(parent, role)`. Roles are brand/title 25, heading 17, body 14, small 13 and meta 12 UI units.
Spectral is used for large headings; Alegreya Sans for controls. Locale fallback stays native for Korean, Chinese and
Russian. `Material.ReminderFont` remains the compatibility name used by the completed reference implementation.
Do not rename it across the feature merely for a global rollout.

Use 14-unit section padding and gaps, a 30-unit minimum form row, 12-unit Home card gaps and a consistent right-hand
control column. Height follows wrapped labels and disabled reasons. Home uses two feature columns at the minimum
width and three when wider. Action-card height follows actual title and description measurements.

Hover uses painted relief; press uses a recessed state; focus uses the field's painted outline. Disabled controls keep
their shape, quieter ink and a prerequisite explanation. Repeated identical prerequisites are drawn once per run in a
section, while every control retains its full help. Selection has an outline and relief as well as a warmer material.
Warnings, validation and error text keep their semantic colors. Native drag targets and valid / invalid drop behavior
remain feature-owned; the rule builder's painted chips and insertion target remain the reference.

No continuous animation is added. Existing bounded fades and wheel easing honor Home's Reduce window motion setting.
No component polls a feature or writes saved state. Existing scopes cover build/layout/search work. The second pass adds
`settings.companion` and read-only scene/visibility gauges for the isolated sample workspace; it adds no background polling.

Ordinary sections use exactly the same `card`/`walnut` source as Reminders Appearance, When and Sound. A frame's
`twichSettingsPanel` records that face; `Material.Card` must neither hide it nor stack a second face/grain on it. Canvas wells
stay recessed. Header, selected and primary treatments have distinct roles; do not invent page-level brown/red tints.

## Organization and progressive disclosure

Start with the player's task in one sentence. Show common settings first. Put full technical explanation behind `?`;
keep privacy, money, sharing and destructive consequences visible. `SettingsDesign.SectionSummary` contains curated
summaries where taking a first sentence would conceal an important consequence.

Secondary sections are chosen per page in `SettingsDesign.pages`, not by guessing from words such as "advanced".
Individual headers may set `header.settingsSecondary = true` for data-driven catalogs such as Camping professions;
this remains a disclosure within its task, even when other common sections in that task start open.
Search and direct navigation expand the containing section before scrolling to a control. Disclosure state is transient;
it never belongs to a profile. Existing card rules, previews, import/export and specialized editors keep their workflows.
Retain their purpose-built tables and editors when they serve their task better than an ordinary form.

Long forms may declare explicit task groups in `SettingsDesign.tasks`: one player task is visible at a time, while the
feature's normal tabs remain available. Task selection is transient and cached with the page. Search/direct navigation
selects the containing task first. Optional integrations show only groups with described sections; do not offer empty modes.

`SettingsCompanion` reuses the Reminders placement/frame/connector family for persistent samples on Notifications, Healer
Watch, Chronicle and Navigation. It owns one frame and at most four private scenes. `Supports(key)`, `Update(view)`, `Hide()`
and `Toggle(view)` are settings-local APIs; the feature owns all configuration. `SceneCount()` is read-only. Clickable sample
regions navigate to stable setting IDs; they never apply a value. Search, page changes and close hide the workspace, and
closed refreshes cannot restore it. Existing actual-position previews remain separate explicit actions. Do not pin a live
notification, start a route or read journal history merely to draw a settings sample.

Sidebar shortcuts follow Everyday, Adventure and Tools. All features opens the complete registered catalog. A selected
feature outside those shortcuts appears under More features. The footer always opens the existing Profiles page.
Appearance lists real appearance pages. Changed settings means **currently different from defaults**, not history.

## Artwork and source files

Reuse `Icons.Apply(texture, id, size)` for feature recognition; keep a text label beside each icon. Runtime icons use
64 pixels, with 32-pixel `-small` variants at 26 UI units and below. Preserve real alpha and edge color bleed.

Painted components: `assets/craft-{frame,button,selection}-source.png`, prepared by `tools/make_craft_art.py` into
`media/style-v2/craft/`. Quiet materials: `media/reminders/materials/`, prepared by
`tools/make_reminder_materials.py` from the existing source materials. See the exact provenance in the
[Reminders revision record](reminders-revision/implementation.md).

Home reuses the six settings icon sheets, the healer vessel, sleeping bag and reminder artwork. One new source,
`assets/settings-satchel-source.png`, supplies `media/icons/magicInventory{,-small}.tga` through
`tools/make_settings_home_art.py`. It was generated once with the built-in image tool: a walnut/chestnut adventurer's
satchel, aged bronze clasp, upper-left light, broad silhouette, genuine transparent background, no text or magic glow.
No reference image was cut into runtime UI. Sources and documentation stay out of packages via `.pkgmeta`.

```lua
local W, M = R.SettingsWidgets, R.SettingsMaterial
local save = W.Button(parent, "Save", 110, "secondary", onSave)
R.SettingsCraft.Control(save, "confirmation")
local choice = W.Dropdown(parent, 220, onPick)
choice:SetChoices(choices)
local tab = M.Segment(parent, "Appearance", 120, openAppearance)
tab:SetSelected(true)
```

## Verification limits

See [the second-pass workflow review](settings-second-pass.md) and [rollout tracker](settings-modernization.md) for actual runs and page status. Simulator screenshots are
structural evidence: the simulator substitutes Friz Quadrata for addon fonts. Handler checks do not exercise pointer
hit testing, keyboard focus, real drag/drop, combat taint or reload persistence. Confirm those in WoW: Forever before
claiming real-client acceptance. No live client data is used by the simulator scenarios.

Magic Inventory's rule badges use the shared `chip` sheet; compact rows use walnut faces and the existing selection
sheet. Illustrated button contents sit in a child frame above the button shell so shell artwork cannot cover icons.
The new reagent illustration is `media/icons/magicReagents{,-small}.tga`, sourced from
`assets/magic-reagents-source.png`; conversion follows the existing alpha-aware icon pipeline.
