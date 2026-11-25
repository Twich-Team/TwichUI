# Quality of life: layout exploration

**Design proposal, not implemented or visually approved.** Source-inspected against `TwichUI_Settings/pages/QoL.lua`, `Window.lua`, `Design.lua`, `Kit.lua`, `Cards.lua`, `previews/QoL.lua`, the settings design system and UX01 in the product roadmap. This document compares two page arrangements; the feature behaviors and stored settings remain unchanged. Dimensions are logical UI units, starting estimates for an annotated wireframe and later visual review, not measured screenshots or a claim of in-game verification.

## The shell and constraints

The existing Settings window starts at **936 × 660**, with minimum **936 × 480**. The minimum width equals the default width: a physically narrow screen is accommodated by window scaling, not by a second, smaller logical width. A larger resized window adds content width; evaluate that separately from scaling. `Window.lua` reserves a 54-unit header, 38-unit footer, 212-unit navigation, 14-unit outer padding, a 12-unit nav/well gap, and 12/28-unit inner well margins. The resulting page content is **644 units wide** at minimum; the right inset includes the existing scroll rail. Actual visible vertical space is reduced further by shell insets, the page header and footer. Do not imply that all rows fit at 480 high.

Retain the current shell: crest, TwichUI / Settings brand, 260 × 24 global **Search settings** and close button in the header; grouped page navigation on the left; page well and its scroll rail; current-profile control and conditional reload notice in the footer. Profile controls are in the footer, not a new account sidebar. Keep the existing restrained espresso/walnut surfaces, bronze edges, ivory text and painted `R.Icons`; do not add another window or search box. Existing search results and direct links must reach the actual control, not just the page.

## Page map shared by both proposals

In A, a **feature row** has its existing illustration, a name, one short purpose line, an explicit On/Off state and a separately operable details affordance. The resurrection row also keeps its separate combat-resurrection choice and its current state visible beside the primary control; it may grow to two lines. In B, the rail shows illustration/name/state and the selected detail supplies purpose, consequence and controls. Switches change their existing settings immediately; opening a row changes only presentation. A collapsed row must expose a concise consequence before a primary automation switch can be enabled: show an always-visible purpose/consequence line for summons, resurrection, release, duels and invitation handling (including battleground-only and Shift override for release). Retain the complete qualifications and warnings in detail; never make opening detail a prerequisite to turning a switch off. Keep the separate independent error-speech switch accessible even though it currently sits under the Hide error messages card. Use names in the table as labels, not abbreviations whose meaning depends on a tooltip.

| Group and proposed row | Existing feature / detail contents to preserve |
|---|---|
| Offers & invitations · Accept summons | Primary `qolSummons`; allowed senders and wait. Leatrix overlap, acceptance consequences and sample remain available. |
| Offers & invitations · Accept resurrection | `qolResurrect`; combat-resurrection option with its heuristic and low-health warning. Sickness, Hardcore and exclusions remain explained; sample. |
| Offers & invitations · Release in battlegrounds | `qolReleasePvP`; wait, Shift override, exclusions and no-retry behavior; sample. |
| Offers & invitations · Decline duel requests | `qolDuels`; allowed people and separate lethal duel switch, unknown-sender behavior, Leatrix note; sample. |
| Offers & invitations · Accept group invitations | `qolInvites`; allowed senders, group/queue/role/quest-session exclusions, unknown sender; sample. |
| Offers & invitations · Decline group invitations | `qolDeclineInvites`; allowed people, exceptions and precedence of accepted invitations, unknown sender; sample. |
| Interface · Quick Keybind button | `qolQuickKeybind`; Game Menu location and combat restriction; sample. |
| Interface · Group Finder zones | `qolGroupFinderZones`; leader-only data, same-zone mark, stale search and narrow-list omission; sample. |
| Messages · Hide error messages | `qolHideErrors`; important-errors exception and distinction between hiding text/sound and silencing speech only; Leatrix note and sample. |
| Messages · Silence error speech | Independent `qolHideErrorSpeech`; preserves text, uses the game's audio option and restores it under the existing rules. Explain it is unnecessary while errors are hidden; it remains independently operable. |
| Sparkles · Quest item sparkles | `qolLootSparkles`; game's choice of targets, restoration/deferred combat behavior and full-restart warning; no sample currently declared. |
| Sparkles · Herb sparkles | `qolHerbSparkles`; current `R.QoLGathering.Status()` note, one-node targeting, combat/player proximity and addon/manual-setting pauses, shared settings restoration; no declared sample. |
| Sparkles · Ore sparkles | `qolOreSparkles`; same status/constraints, independent switch, shared restoration; no declared sample. |

There are 12 existing cards and 13 independent primary switches when error speech is counted separately; three dependent switches (combat resurrection, important errors and duels to the death) and six choice controls bring the total to 22 persisted controls. The current home overview counts 11, omitting both error switches. Treat that as an existing count limitation for review, not authorization to change counts or defaults in this design batch. Nine cards explicitly declare previews; the three sparkle cards do not. Preserve dynamic Leatrix notes and all disabled reasons (`K.Under`), not merely their current text snapshots. The functional audit is the authority for exact values, defaults and all compatibility details.

## Option A — categorized rows with inline detail

A single full-width list inside the existing page scroll. Four quiet group headings organize the thirteen rows in the order above. At the 644-unit baseline, reserve roughly 16 units inner padding, 28–32 for the icon, a flexible text column, a switch/state area and a 32–40-unit disclosure target. Begin with approximately 58–64 units per row; grow for wrapping, status notes, larger fonts and interaction targets. The purpose line may wrap instead of shrinking or clipping. No separate category tab bar is necessary.

The disclosure expands a detail block immediately under that row, using the same width and page scroll. Keep the primary toggle in the row and show all feature-specific controls, disabled reasons, short consequence and an optional existing sample in the detail. For resurrection, show the combat-resurrection switch, its On/Off state and a concise warning (“Combat resurrection can return you to a fight with low health”) alongside the primary switch even while the row is collapsed; preserve its disabled reason when the parent is off. Detail provides the existing heuristic and exceptions. Error speech is a separate row, never dependent on hiding errors. The sparkle status should remain visible when relevant rather than disappearing behind the detail.

**Interaction:** expand/collapse without toggling the feature; click the switch without expanding. Initially all rows are collapsed unless global search/direct navigation targets a control. Prefer one expanded row at a time to bound scrolling; closing the old row must not write values. Keep a just-opened heading in view and focus on its disclosure; if collapsing would hide the focused control, move focus to that disclosure first. Only one detail stays open at a time; an owner can review this choice.

## Option B — two-pane feature browser

Use the same 644-unit content area for a roughly **200-unit feature list + 12-unit gap + 432-unit detail pane**, before internal padding and any scroll rail. The left list has group labels and compact name/state rows; the right shows the selected feature, its full primary and dependent controls, warnings and optional sample. Switching selection changes the right pane only. If the first item is selected automatically, no setting changes; the selection is transient.

This makes comparisons between nearby features fast and avoids a long expanded page, but repeats the persistent left-side navigation pattern inside a shell that already has a 212-unit page navigation. Two independently scrollable panes and the outer page scroll complicate wheel targeting, focus reveal and keyboard traversal; a 432-unit detail width must accommodate controls currently designed for a 236-unit control plus their labels. A narrow physical display scales the entire shell, making that pane visually smaller, not logically wider. At **936 × 480**, both panes have much less height; if their content cannot fit, a selected-feature subview with a visible Back to features action is preferable to clipping, but that adds a second interaction model. No automatic breakpoint is prescribed until measured with actual fonts and controls.

## Comparison and recommendation

| Criterion | A: inline rows | B: browser |
|---|---|---|
| Discover and scan | Names, purposes and state visible together; grouped long list | Dense names/states; purpose and controls require selection |
| Access to settings | One disclosure, then immediate controls | One selection, then immediate controls |
| Scroll | One established page scroll; opening a detail lengthens it | Less detail mixed into list; two inner scroll regions; outer page retains header/reset |
| Minimum-height / scaled display | Full content width for controls; more vertical scrolling | Narrower detail plus short independent panes; compact but more focus/scroll work |
| Accessibility | Full-width labels and established reveal path; disclosure focus must be managed | Requires clear selected row, pane focus and reliable wheel/keyboard handoff |
| Reuse and effort | Local QoL presentation over existing rows, cards/disclosure and page scroll | More page-specific selection, pane layout and nested scrolling; still no new framework |

**Recommend Option A** for first implementation: it uses the full 644-unit content width and the existing single-page scroll, while keeping switches and purposes visible. It is a modest evolution of current Settings rather than a new navigation model. This is a recommendation for owner review, not an approval or a claim that the wireframe has been visually validated. Both options require scrolling and explicit preservation of control-level search targets.

## Implementation notes for A, subject to approval

- Keep the page's existing settings descriptors, identifiers, getters/setters, default values and `K.Under` dependencies. Reuse `K.Note`, the existing card/row control renderers, `Material` disclosure/segment/scroll treatments and existing icons where they fit. Adapt only QoL presentation; do not create a generic feature-browser framework or duplicate controls/settings objects. Preserve the other pages' card behavior.
- An expanded row includes its current control values and disabled prerequisite explanations, concise “Good to know” text and, when available, its existing `previews/QoL.lua` sample. Show only the expanded feature's sample; release its transient work on collapse/page hide. Keep long help discoverable from the detail and existing tooltips. Confirmation, effect timing, Leatrix overlap and gathering status remain dynamic.
- Global Settings search stays the only text search. For a search result or direct link to a child setting, open its feature first, lay it out, scroll it into view and retain existing highlight/focus behavior. Preserve Esc and dropdown handling, tab order, visible keyboard focus, current-page refresh after profile changes and restored scroll position where practical. Do not move focus to a hidden control or let a collapsed group conceal a search target.
- At 936 × 660 and 936 × 480, preserve the outer shell and the single scroll rail. At larger widths allow text to breathe rather than increasing icon size. At high UI scale or large font, wrap purposes and warnings, grow rows and details, and retain full-size switches/disclosures. Do not rely on color alone for On/Off, warnings, disabled state or selection. Check physical screen fit and scale using the existing `WindowScale`/`Fit` behavior; no invented smaller minimum.
- Focused future verification: each existing control reachable by direct navigation/search and correct conditional state; no mutations on open/close; toggles, saved values and profile changes retain behavior; dynamic notes and all nine samples appear in their correct details; repeat expand/collapse without duplicate frames/hooks; focus, scroll, Escape and disabled explanations remain usable. Check normal and minimum window heights, long text and enlarged fonts, including real-client appearance if owner-directed. Simulator evidence is structural and does not establish native visual acceptance.

## Decisions for owner review

Choose A or B and confirm the proposed one-open-detail behavior and separate error-speech row. Approve the grouping and visible safety warnings, then review annotated visuals at default and minimum height before implementation. Local search/category chips are not recommended for these 13 feature rows unless user testing shows the existing global search and headings insufficient.
