# Project Revision — Complete Requirements and Design Handoff

Prepared: November 10, 2026  
Project: TwichUI addon for World of Warcraft Forever  
Revision: Reminders settings, interactive preview, template catalog, When builder, and their shared visual treatment  
Intended recipients: ChatGPT as implementation planner; Codex as implementation agent

***

## Document authority, evidence, and limitations

This document preserves decisions from the accessible conversation, retrieved project memories, supplied screenshots, and available project-document excerpts. It does not constitute an independent audit of the current repository.

The following were available:

- The conversation covering template-catalog design, Claude implementation, Codex preparation, image-generation verification, Codex implementation, and user rejection of the visual result.
- User-pasted Claude and Codex reports.
- Current-client screenshots and the approved preview render shown in the conversation.
- An approved catalog render shown earlier in the conversation.
- Project-document excerpts from `PROJECT_BRIEF.md`, `STATUS_AND_BACKLOG.md`, `SIMULATOR_HANDOFF.md`, and `simulator-lab.md`.
- Retrieved memories of earlier Reminders design discussions.

The following were not independently inspected:

- Current local repository code.
- Current `docs/reminders-style-upgrade.md`.
- Current `AGENTS.md`.
- Current local backlog modifications.
- Codex’s generated simulator screenshots.
- The actual `REMINDERS_WHEN_BUILDER` image.
- Current Git state or the implementation diff.

### Evidence terminology

| Term | Meaning |
|---|---|
| Approved | Explicit user decision, accepted visual reference, or established requirement subsequently carried forward. |
| Proposed | Assistant recommendation or interpretation without clear user approval. |
| Unresolved | Missing information, conflicting instructions, or a decision not established in accessible evidence. |
| Reported implemented | Claude or Codex said it was implemented; not independently verified here. |
| User-confirmed | The user reported observing the behavior in the real client. |
| Screenshot-observed | Visible in an image supplied in this conversation. |
| Historical snapshot | Dated project material that may be superseded. |

Current code and fresh evidence outrank older reports for implementation state. Explicit newer user decisions outrank older planning restrictions for requested scope. The project brief expressly warns against treating proposals or reports as verified implementation. [pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws](https://pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws.com/projectfiles-prod/gateway-object-store/repos/files-9f57862b6fe94fc8323efb4e517c6350/downloads/5921924e0ff7ca967b97cdced03a147fdb8df8c2/PROJECT_BRIEF.md?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Checksum-Mode=ENABLED&X-Amz-Credential=ASIA2F3EMEYEVX5UQXVL%2F20261110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261110T225642Z&X-Amz-Expires=600&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEHoaCXVzLWVhc3QtMSJHMEUCIQCeQrPEVwzWT0mSL%2FNDfM6hm%2BBrnQ0jTjiqeqiFA00DBgIgH0SF8qdP0E8WME%2Fwk4DcXN%2Bl%2Bpzqs7XZfTzIazyEcv0qpwUIQhABGgw2OTk3NTMzMDk3MDUiDJzmk2TCR4ZUSu3GLCqEBRW3JAINlPHWqjH7pTzW%2BnwW4x5xN4RJf2%2F4Yc0940J%2BwWUZkhqdUk1ZQQW%2FiItN3i9ZkOSvV%2F%2FLiKPgQ%2BUx2HTafpmpWcsK6lKrCF0l%2Binn9S1w%2FK%2F%2BaP039kqcZZozY0xL3ZM8xd7%2BjTMO9bsiqL1GFNMXEpNuRRAGB0JjhaR0FYEzRwKlDFe0pahVJh8TWLQBY%2BZwh83%2BdGLkH618XRcBipzGT%2Bgj3WUEXpPAkgLxVyIumkckynbB%2Fd3RPbnU%2BNICj87ywLIb25dIYMsDblfamfHkR1gfkqmoe2Cjv0kMrLC3t75KnL54WcIat4h3bvAaWuPNbSO2ylzmGXcJIoaRkx0N9TqCHLML6YNLr91ucRMPzrZ2Q0tvOAPzoQ5aE%2Btx3eqQ3kTbY2fsG%2FCfWVTr3Z5wpKcAeG6OJvRFsZMSN32PGwmCxjK5xQifMtJP1Qqg3O%2FgHupKYBa83wnVJEtQnaJMpfJWL%2F%2BXgqaReNA8Eq7QOI4AYBUW0g2YvEYWjUA%2B%2FTGn%2B%2Fv4J1DE0rkZ%2FpIeK%2BC6fRpO6uciWGXikVo3osEbwIIqIpfm6TREVSyuXlUmeCFyKexnn2zaf53UT%2BAM8EbqmCqZ%2BtVQsVYwt0L9QIn%2BT19gOY4NJrOGkpg4sMJn5AmkiRVB8oxrw4hcMjqRWa6UJqC33dD5SIZLPBeo0BThObKFY3LCjbBw62AjAXzDDEDkT6%2F5Px6u8%2BbFX%2BWtVcmPh2FGEPysUG2%2Fw56CrkKZNhglJRaymwMM2e118BUmbN3an9UgUcS7fPSqxhLey92DpsYIhwls6jmqeJjzGM6eeDrHyE7xdYaY%2BB8i5lZdWwXPNyG7gbVpBmWdBrxI3elHMMGlzdcGOpABquFj3FoWrWroNbCBvXEgc7Jkzh%2Bd4T%2FKZLzX8tQfaFwr5Pe6VdyoRX0BDBYqPul76R83lCXQonEzzWymQeZ5t2q7uEJCuKMnBVow%2BrorsDyq%2Bka%2BPvV58JSbaKwqqb221kwKsJdUQ1KrHRZqfGjq%2BUmwWzNS3%2Fru30KS9eJ3Z2%2BXH3USXEZDDcy4xniP3ras&X-Amz-SignedHeaders=host&response-content-type=text%2Fmarkdown%3B%20charset%3Dutf-8&x-id=GetObject&X-Amz-Signature=69527b4f8f0b018b78b31725ae9f427165691beb95d7eb7429e91e70a5b01da0)

### Source key

- **C1:** Early November 10 catalog mockup, user approval, and requirement addition.
- **C2:** Claude catalog implementation report, pasted at 12:41 PM and again at 1:18 PM.
- **C3:** Current-client screenshots supplied at 1:21 PM.
- **C4:** Claude preview-companion implementation report, 1:31 PM.
- **C5:** User confirmation at 1:33 PM that the companion preview works.
- **C6:** Claude repository-preparation report, 1:41 PM.
- **C7:** User reference clarification: only `REMINDERS_PREVIEW`, `REMINDERS_TEMPLATE_CATALOG`, and `REMINDERS_WHEN_BUILDER`.
- **C8:** User correction at 2:34 PM: Codex should not stop at bounded milestones; it should implement and compare against mockups.
- **C9:** User confirmation at 3:00 PM that image generation succeeded and saved correctly.
- **C10:** Full implementation prompt supplied at 3:03 PM.
- **C11:** Codex implementation report pasted at 3:47 PM.
- **C12:** User’s rejection and accompanying client screenshots at 3:53 PM.
- **C13:** Assistant’s proposed correction prompt following C12. Its being sent or executed is not established.

***

## 1. Executive Overview

### 1.1 Application and subsystem

TwichUI is a World of Warcraft Forever addon with a substantial settings interface and multiple features. This revision concerns Reminders and the visual/UI infrastructure needed to make it the initial prototype for a polished, reusable settings style.

This is not the TwichUI Workbench project. Workbench’s web application, orchestration, databases, and provider management are outside this revision.

### 1.2 Primary goals

1. Closely implement the approved Reminders mockups.
2. Make reminder configuration approachable without sacrificing existing rule semantics.
3. Provide an attached, interactive appearance preview.
4. Replace individual template-creation buttons with an illustrated catalog.
5. Provide an attached/pop-out When builder with understandable condition grouping and drag-and-drop.
6. Establish consistent controls, materials, typography, and selection treatment.
7. Use actual simulator renders to compare and refine the implementation.
8. Preserve player configuration, runtime behavior, compatibility, and safety.

The user wants this to feel like a crafted fantasy interface, not an engineering dashboard or a minimal functional approximation.

### 1.3 Current problem

Codex reported completing the upgrade and reviewing simulator screenshots. The user’s real-client screenshots show a major gap from the approved render:

- Checkboxes remain where pill switches were expected.
- Buttons and fields retain legacy styling.
- Text colors, sizes, and hierarchy do not match.
- Tabs are not consistently styled.
- Reminder selection lacks the approved treatment.
- The When picker has overflowing category tabs.
- The user reports drag-and-drop is absent.
- Overall proportions, panel organization, and companion presentation differ substantially.

The current client and approved preview render support the visual mismatch directly. [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/95709f3d-afdb-4b44-9684-bb989693740f/image.jpg)

### 1.4 Intended completed experience

A player opens Reminders, selects a reminder from a clear list, and edits a compact set of appearance, condition, and sound controls.

The adjacent preview:

- Shows the selected reminder independently of whether it is active.
- Updates as appearance changes.
- Lets the player click artwork or text to find the corresponding setting.
- Clearly distinguishes editing preview from actual in-game visibility.

The same companion location can display the template catalog or When builder without overlapping competing windows.

### 1.5 Explicitly outside scope

- TwichUI Workbench.
- Addon-wide architecture or code-quality investigations.
- Automatic restyling of every addon page.
- New condition types merely to match mockup illustrations.
- A replacement rule engine or node-graph framework.
- Broad unrelated refactors.
- Agent teams by default.
- Simulator engine repairs.
- Unapproved dependencies or installations.
- Destructive Git cleanup.
- Commits, pushes, publishing, or external submissions without authorization.
- Live game configuration or `WTF/SavedVariables` modifications by the coding agent.

A broader aspiration for a powerful, versatile Reminders system comparable in ambition to WeakAuras was discussed. It is not authorization to reproduce WeakAuras or add an unspecified condition library in this revision.

***

## 2. Current Implementation

### 2.1 Existing reminder behavior

Earlier client screenshots show:

- Reminders master enable control.
- A reminder list with enabled state and current showing/hidden state.
- Reminder naming.
- Duplicate and Delete.
- Display mode.
- Artwork selection.
- Text/“Words.”
- Conditions.
- Sound selection and playback control.
- Placement, size, and effects.
- Test diagnostics.
- Profile context and reset controls.

The example reminders include:

- `Wizard Oil Missing`
- `Well Fed reminder`
- `Shield reminder`

The screenshots show profile `TwichUI Adventure`, shared with two other characters. This is an observed example, not a required profile name or sharing default. [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/95709f3d-afdb-4b44-9684-bb989693740f/image.jpg)

### 2.2 Catalog: Claude-reported implementation

C2 reports:

- `New reminder` opens a companion catalog.
- Two-column layout.
- Five supported templates plus Custom.
- Name, image, short description, and `Use template`.
- Esc, close, settings close, or leaving the page dismisses it.
- Creation uses `P.Create` → `RM.Create`.
- New copies have independent identities and start disabled.
- Success selects the reminder and opens its editor.
- Refusal leaves the catalog open with an explanation.
- Reported limit: 24 reminders.
- Newer-format profiles can refuse creation.

Reported catalog/template names:

- Missing shield
- Ammunition
- Missing weapon enchant
- Well Fed ran out
- Missing equipment or item
- Custom reminder

These differ from shorter illustrative mockup names. Exact final naming has not been conclusively normalized.

### 2.3 Attached preview: Claude-reported implementation

C4 reports:

- New `RemindersPreview.lua`.
- Existing `D.NewSurface` / `D.DrawSurface` reused.
- Old large inline preview removed.
- Page redraw drives companion updates.
- No new event listeners.
- Frame created once.
- Catalog hides preview; cancellation or creation restores the appropriate preview.
- Placement flips left when needed and clamps to screen.
- `Show on screen` / `Hide preview` moved into companion.
- No sound or condition evaluation required for preview.

The user confirmed the preview was working in the client in C5. That confirmation does not establish every lifecycle or edge-placement check.

### 2.4 Repository preparation: Claude-reported findings

C6 reports:

- `docs/reminders-style-upgrade.md` created.
- `AGENTS.md` created.
- `.pkgmeta` updated to exclude `AGENTS.md`.
- Local `STATUS_AND_BACKLOG.md` updated.
- Catalog and preview already committed in `2e0c5fe5` on `feature/style`.
- The tree was clean at that inspection.

This superseded earlier assumptions that those functional changes were uncommitted. Current Git state is unknown.

### 2.5 Reported code map

| Path/symbol | Reported role |
|---|---|
| `TwichUI_Settings/pages/Reminders.lua` | Page, selection, creation entry, redraw |
| `TwichUI_Settings/pages/RemindersCatalog.lua` | Template catalog |
| `TwichUI_Settings/pages/RemindersPreview.lua` | Preview companion |
| `TwichUI_Settings/pages/RemindersEditor.lua` | Editor sections |
| `TwichUI_Settings/pages/RemindersDesigner.lua` | Existing condition designer |
| `!!!TwichUI/reminders/Config.lua` | `RM.Create`, template definitions/display metadata |
| `reminders/Display.lua` | `D.DrawSurface`; full current path must be checked |
| `RM.TemplateDisplay(kind)` | Read-only template display metadata |
| `PV.Place` | Reported shared companion placement |
| `Material.lua` | Style-v2 materials; exact path to inspect |
| `media/style-v2/` | Leather/bronze materials |
| `FrameLook.lua` | Existing frame shell |
| `media/guildbank/` | Potential frame assets |
| `Window.lua` | Scroll-to-position function was initially local |

These paths and symbols derive from reports, not direct code inspection.

### 2.6 Latest Codex report

C11 claims:

- Compact Appearance, When, Sound, Advanced, Test organization.
- Click artwork/text to reveal and highlight controls.
- Illustrated catalog.
- Attached When editor reusing existing designer.
- Shared companion placement and cleanup.
- 187 tests passing.
- 83 simulator handler/state checks across four scenarios.
- 56 settings pages constructing.
- Screenshot comparison for editor, catalog, When, and narrow fallback.
- One generated leather-gauntlet image and reused oil/scroll/shield/ammunition/food assets.
- Actual-client acceptance pending.

C12 rejects visual completeness. Therefore the implementation must not be described as visually accepted.

***

## 3. Complete Feature Requirements

### Common requirement conventions

Unless specified otherwise:

- No new setting or default is authorized merely by listing a requirement.
- Existing values, validation, storage, and defaults must be preserved.
- Error details should be concise and actionable.
- Exact numeric dimensions and timing are not established.
- “Approved” concerns requested behavior, not implementation verification.
- Source references identify the discussion establishing the requirement.

### FR-001 — Compact Reminders editor

**Status:** Approved.  
**Source:** C7, C8, C10, C12; preview mockup.

- Present reminder selection and primary editing together.
- Prioritize Appearance, When, and Sound.
- Keep Advanced and diagnostics secondary.
- Consolidate redundant introductory/overview material.
- Preserve necessary functionality omitted from illustrative renders.
- **Acceptance:** Primary editing resembles the approved composition and does not depend on traversing the former long-form page.
- **Dependencies:** UI-001–UI-010; FR-002.

### FR-002 — Reminder list and selection

**Status:** Approved.

- Show existing reminders with recognizable artwork, names, and meaningful state.
- Selecting a row updates editor and preview consistently.
- Distinguish enabled state from current showing/hidden state.
- Handle long names without destroying alignment or access.
- **Defaults:** Existing selection behavior unless deliberately documented otherwise.
- **Acceptance:** List, editor name, and companion refer to the same reminder.
- **Source:** C10–C12; preview render.

### FR-003 — Enable controls

**Status:** Approved.

- Retain master feature enable and individual reminder enable.
- Use the approved switch presentation.
- Visual replacement must preserve setters, validation, and saved data.
- **Acceptance:** On/off behavior is unchanged; no visible legacy checkbox remains where a switch is required.
- **Dependencies:** UI-011; FR-015.
- **Source:** C12.

### FR-004 — Attached live preview

**Status:** Approved; basic behavior user-confirmed.

- Display selected reminder alongside editing.
- Update name, image, text, and relevant appearance.
- Remain available while the main editor scrolls.
- Reuse existing renderer.
- **Acceptance:** Correct selection and edits update without enabling the reminder.
- **Source:** C4, C5, C10.

### FR-005 — Interactive preview navigation

**Status:** Approved; reported implemented, pointer verification pending.

- Click preview artwork/text to reveal relevant controls.
- Briefly highlight the destination.
- Clicking navigates; it does not change reminder configuration.
- Provide restrained discoverability.
- **Acceptance:** Correct target is revealed and highlighted, including after scrolling.
- **Configuration:** No extra preference established.
- **Dependencies:** FR-004, UI-018.
- **Source:** Earlier interactive-preview discussions; C10.

### FR-006 — Isolated, silent preview

**Status:** Approved.

- Disabled reminders remain previewable.
- Preview does not enable, evaluate, or mutate live reminder conditions.
- Preview does not play reminder-trigger sounds.
- **Acceptance:** A disabled reminder stays disabled; live state remains unchanged.
- **Source:** C4, C10.

### FR-007 — Explicit on-screen preview

**Status:** Approved preservation requirement.

- Preserve `Show on screen` / `Hide preview`.
- This temporary display is separate from normal active reminders.
- Clean up when settings close or the relevant page is left.
- **Acceptance:** No orphaned temporary display after closure/reopening.
- **Open detail:** Combat cleanup policy is reported as a client check, not fully specified.
- **Source:** C4, C10, C11.

### FR-008 — Preview sizing modes

**Status:** Unresolved as an explicit approved functional commitment; visible in approved render.

- Mockup includes `Actual size` and `Fit`.
- C13 explicitly proposed implementing both, but user delivery/execution of that prompt is unknown.
- **Expected if included:** Labels correspond to real modes; fitting must not modify saved reminder scale.
- **Acceptance:** Distinct correct behavior and honest mode indication.
- **Default:** Unknown.
- **Dependencies:** FR-004.
- **Source:** Preview render; C13.

### FR-009 — Honest visibility/status explanation

**Status:** Approved principle; exact labels unresolved.

- Distinguish master enable, reminder enable, live visibility, and preview visibility.
- Preserve honest condition-state explanations.
- Mockup includes `Hidden in game` and explanatory text.
- **Acceptance:** No label incorrectly implies a preview is a live active reminder.
- **Dependencies:** FR-006, FR-019.
- **Source:** Approved render; existing condition-designer direction.

### FR-010 — Catalog entry and cancellation

**Status:** Approved.

- `New reminder`/`+ New` opens catalog.
- Opening creates nothing and preserves selection/configuration.
- Closing/canceling creates nothing.
- **Acceptance:** Close, Esc, navigation away, and settings close leave reminder data unchanged.
- **Exact entry label:** Unresolved between actual `New reminder` and mockup `+ New`.
- **Source:** C1, C2.

### FR-011 — Illustrated template catalog

**Status:** Approved.

- Each template has artwork, name, short description, and `Use template`.
- Include existing supported templates and a separate `Custom reminder`.
- All entries remain accessible, including a fifth template requiring another row.
- **Acceptance:** No inaccessible cards or cutoff actions.
- **Dependencies:** UI-013, UI-019.
- **Source:** C1, C10.

### FR-012 — Independent template creation

**Status:** Approved.

- Use canonical validated creation path.
- Deep-copy mutable configuration.
- Assign unique identity.
- Start disabled.
- Select new reminder and open its editor.
- Catalog closes on success.
- **Acceptance:** Repeated copies do not share state; edits/deletion do not mutate template definitions.
- **Source:** C1, C2, C10.

### FR-013 — Creation refusals and limits

**Status:** Approved preservation requirement.

- Preserve current limit, reported as 24.
- Preserve refusal for incompatible/newer-format profiles.
- Keep catalog open on failure and explain why.
- **Acceptance:** No partial creation, selection corruption, or silent failure.
- **Dependencies:** FR-012.
- **Source:** C2.

### FR-014 — Custom reminder

**Status:** Approved.

- Distinct entry using existing custom-creation flow.
- Same limit/compatibility safeguards.
- **Defaults:** Existing custom defaults; exact content unknown.
- **Acceptance:** Creates only through canonical path and opens the new draft.
- **Source:** C1, C2.

### FR-015 — Required configuration safeguards

**Status:** Approved.

- Clearly expose essential missing inputs.
- Guide user to complete them.
- Do not interpret empty required conditions as “always show.”
- Prevent invalid enabled configurations.
- **Acceptance:** Existing incomplete equipment/item template cannot become misleadingly active.
- **Dependency:** Inspect current validation before modification.
- **Source:** C1 requirement addition; C10; repeated review questions.

### FR-016 — Search and category filtering

**Status:** Unresolved for this execution scope.

- Approved catalog mockup shows `Search templates…`, `All`, `Preparation`, `Equipment`.
- Functionality was repeatedly deferred in implementation prompts.
- C13 proposed explicitly including it, but the user has not confirmed that scope change.
- **Acceptance if included:** Filters only catalog entries; no data mutation; clear empty results.
- **Default if included:** All/no query, inferred from mockup rather than independently confirmed.
- **Source:** C1, C10, C13.

### FR-017 — Attached When builder

**Status:** Approved.

- Open from `Edit conditions`.
- Use its own appropriately sized companion/custom frame.
- Reuse existing designer logic.
- Return to appearance/preview without losing configuration.
- **Acceptance:** No duplicate designer implementation or competing companion.
- **Source:** Earlier builder discussion; C10.

### FR-018 — Understandable rule editing

**Status:** Approved.

- Sentence-like conditions.
- Clearly bounded All/Any groups.
- Guided condition picker.
- Separate character targeting from predicates.
- Preserve supported rule editing.
- **Acceptance:** User can understand grouping without reading technical diagnostics.
- **Source:** Project backlog; builder discussion. [pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws](https://pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws.com/projectfiles-prod/gateway-object-store/repos/files-9f57862b6fe94fc8323efb4e517c6350/downloads/5921924e0ff7ca967b97cdced03a147fdb8df8c2/STATUS_AND_BACKLOG.md?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Checksum-Mode=ENABLED&X-Amz-Credential=ASIA2F3EMEYEVX5UQXVL%2F20261110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261110T225642Z&X-Amz-Expires=600&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEHoaCXVzLWVhc3QtMSJHMEUCIQCeQrPEVwzWT0mSL%2FNDfM6hm%2BBrnQ0jTjiqeqiFA00DBgIgH0SF8qdP0E8WME%2Fwk4DcXN%2Bl%2Bpzqs7XZfTzIazyEcv0qpwUIQhABGgw2OTk3NTMzMDk3MDUiDJzmk2TCR4ZUSu3GLCqEBRW3JAINlPHWqjH7pTzW%2BnwW4x5xN4RJf2%2F4Yc0940J%2BwWUZkhqdUk1ZQQW%2FiItN3i9ZkOSvV%2F%2FLiKPgQ%2BUx2HTafpmpWcsK6lKrCF0l%2Binn9S1w%2FK%2F%2BaP039kqcZZozY0xL3ZM8xd7%2BjTMO9bsiqL1GFNMXEpNuRRAGB0JjhaR0FYEzRwKlDFe0pahVJh8TWLQBY%2BZwh83%2BdGLkH618XRcBipzGT%2Bgj3WUEXpPAkgLxVyIumkckynbB%2Fd3RPbnU%2BNICj87ywLIb25dIYMsDblfamfHkR1gfkqmoe2Cjv0kMrLC3t75KnL54WcIat4h3bvAaWuPNbSO2ylzmGXcJIoaRkx0N9TqCHLML6YNLr91ucRMPzrZ2Q0tvOAPzoQ5aE%2Btx3eqQ3kTbY2fsG%2FCfWVTr3Z5wpKcAeG6OJvRFsZMSN32PGwmCxjK5xQifMtJP1Qqg3O%2FgHupKYBa83wnVJEtQnaJMpfJWL%2F%2BXgqaReNA8Eq7QOI4AYBUW0g2YvEYWjUA%2B%2FTGn%2B%2Fv4J1DE0rkZ%2FpIeK%2BC6fRpO6uciWGXikVo3osEbwIIqIpfm6TREVSyuXlUmeCFyKexnn2zaf53UT%2BAM8EbqmCqZ%2BtVQsVYwt0L9QIn%2BT19gOY4NJrOGkpg4sMJn5AmkiRVB8oxrw4hcMjqRWa6UJqC33dD5SIZLPBeo0BThObKFY3LCjbBw62AjAXzDDEDkT6%2F5Px6u8%2BbFX%2BWtVcmPh2FGEPysUG2%2Fw56CrkKZNhglJRaymwMM2e118BUmbN3an9UgUcS7fPSqxhLey92DpsYIhwls6jmqeJjzGM6eeDrHyE7xdYaY%2BB8i5lZdWwXPNyG7gbVpBmWdBrxI3elHMMGlzdcGOpABquFj3FoWrWroNbCBvXEgc7Jkzh%2Bd4T%2FKZLzX8tQfaFwr5Pe6VdyoRX0BDBYqPul76R83lCXQonEzzWymQeZ5t2q7uEJCuKMnBVow%2BrorsDyq%2Bka%2BPvV58JSbaKwqqb221kwKsJdUQ1KrHRZqfGjq%2BUmwWzNS3%2Fru30KS9eJ3Z2%2BXH3USXEZDDcy4xniP3ras&X-Amz-SignedHeaders=host&response-content-type=text%2Fmarkdown%3B%20charset%3Dutf-8&x-id=GetObject&X-Amz-Signature=50e6fe2b2470422cd549ef127e2a80be3a010fd48e445a218ff4d022e489443f)

### FR-019 — Preserve condition semantics

**Status:** Approved.

- Preserve All/Any, negation, unknown results, validation, identity, and configuration.
- No lossy conversion to match the visual design.
- Do not add condition types to satisfy illustrative mockup content.
- **Acceptance:** Existing rule results remain equivalent after editing/migration.
- **Source:** C10; historical designer requirements.

### FR-020 — Drag-and-drop conditions/groups

**Status:** Approved user requirement; exact mechanics partly unresolved.

- User explicitly objects that drag-and-drop is absent.
- Support arranging conditions into AND/OR grouping.
- Preserve rule semantics and identity.
- **Acceptance:** Required arrangements can be made through actual pointer interaction.
- **Unresolved:** Exact allowed nesting, group dragging, drop geometry, and save timing.
- **Source:** Earlier builder discussion; C12.
- **Supersedes:** Historical “optional” and later conditional wording.

### FR-021 — Safe drag operations and alternatives

**Status:** Proposed implementation details consistent with approved safety goals.

- Clear insertion/drop feedback.
- Cancel/invalid drop leaves original tree intact.
- Reject self-descendant/cyclic movement.
- Non-drag editing alternatives remain available.
- **Acceptance:** No partial or invalid tree after canceled/invalid operations.
- **Source:** Historical non-drag direction; C13.
- **Dependencies:** FR-019, FR-020.

### FR-022 — Shared companion lifecycle

**Status:** Approved.

- Preview, catalog, When occupy shared companion location.
- Preserve selection when switching.
- Restore correct surface after cancel/success.
- Refusal leaves catalog visible.
- Hide/clean up on page/settings closure.
- **Acceptance:** One intended companion, correct state, no orphan frames/listeners.
- **Source:** C4, C10.

### FR-023 — Constrained placement

**Status:** Approved; fallback design unresolved.

- Keep important content and actions accessible.
- Support screen edges and relevant UI scales.
- Flip sides where appropriate.
- Do not rely on clamping that creates inaccessible overlap.
- **Acceptance:** No clipped close/back/action controls or overflowing categories.
- **Source:** C4, C10, C12.

### FR-024 — Preserve existing editor actions

**Status:** Approved.

- Retain naming, Duplicate, Delete, sound selection/test, placement/size/effects, diagnostics, profile context, and reset behavior.
- Styling/reorganization must not silently remove capabilities.
- **Acceptance:** Existing workflows remain reachable and behave consistently.
- **Defaults:** Preserve existing values.
- **Source:** C3 screenshots; C10.

### FR-025 — Asset generation and integration

**Status:** Approved.

- Use successfully tested generation path for needed assets.
- Reuse suitable existing assets first.
- Generate standalone assets, not flattened UI windows.
- Keep UI text in code.
- Inspect transparency, seams, scaling, and small-size legibility.
- **Acceptance:** Runtime assets are usable in actual frames and packaging.
- **Source:** C9, C10.

### FR-026 — Simulator comparison and iteration

**Status:** Approved, explicitly emphasized by user.

- Render actual changed interfaces.
- Open generated images and approved references.
- Compare and correct meaningful differences.
- Cover editor/preview, catalog, and When.
- **Acceptance:** Evidence includes actual comparison findings, not only screenshots existing.
- **Source:** C8, C10, C12.

### FR-027 — End-to-end execution without routine gates

**Status:** Approved.

- Internal phases organize work; do not require user restart/approval each phase.
- Continue through approved scope.
- Ask for consequential ambiguity, external authorization, or material expansion.
- **Acceptance:** Agent does not stop solely because milestone 1 is done.
- **Source:** C8, C10.

### FR-028 — Honest progress reporting

**Status:** Approved.

- Separate implementation, unit tests, simulator handlers, visual comparison, and real-client verification.
- Explicitly report mismatches/placeholders.
- No “complete” claim based solely on tests or construction.
- **Acceptance:** Remaining major visual gaps prevent visual-acceptance status.
- **Source:** Project instructions; C10–C12.

***

## 4. Visual Design and Styling Requirements

No exact hex palette, full pixel specification, font-size scale, corner radius, or fixed margin system was established in the accessible discussion. Derive proportions from approved references and verify against actual runtime behavior; do not invent precision.

| ID | Requirement and acceptance | Status |
|---|---|---|
| UI-001 | Match approved compositions, not merely a brown palette or rough feature arrangement. | Approved |
| UI-002 | Warm worn leather, walnut/espresso interiors, chestnut surfaces. Subtle visible texture; no muddy orange wash. | Approved |
| UI-003 | Aged bronze and selective antique gold; warm ivory primary text, quieter readable secondary text. | Approved |
| UI-004 | Narrow continuous frames, coherent corners/rails, consistent thickness, modest fittings. | Approved |
| UI-005 | Restrained bevels, recessed wells, shallow depth. Highlights remain behind labels/art. | Approved |
| UI-006 | Modest rounded corners on relevant controls, cards, selected rows, containers. | Approved |
| UI-007 | Strong readable heading/control hierarchy; do not retain universally tiny muted gold labels. | Approved |
| UI-008 | Balanced spacing/alignment and consistent padding; support real text lengths. | Approved |
| UI-009 | Main list and editor proportions follow preview target; substantial list well rather than an undersized floating list card. | Approved visual target |
| UI-010 | Advanced/help/test information secondary, not dominant oversized primary panels. | Approved |
| UI-011 | Pill switches instead of the user-rejected square boolean checkboxes on redesigned surfaces. | Approved |
| UI-012 | Rounded shallow-beveled buttons, bronze rims, warm ivory enabled labels, readable disabled labels. | Approved |
| UI-013 | Catalog cards with distinct surfaces, consistent artwork/title/body/action hierarchy. | Approved |
| UI-014 | Styled dropdowns, fields, tabs, segmented controls, close/back buttons. No category overflow. | Approved |
| UI-015 | Richer selected-state gold, rounded selection, coherent row/navigation/editor treatment. | Approved |
| UI-016 | Larger/prominent navigation artwork/text and stronger selected navigation treatment, scoped carefully to this prototype. | Approved direction; rollout extent unresolved |
| UI-017 | Clear hover/pressed/disabled/selected and applicable focus/error presentation; exact error color not specified. | Approved |
| UI-018 | Restrained preview hover affordances and temporary destination highlight; no distracting flash. | Approved |
| UI-019 | Standalone artwork readable at actual UI size; transparent when appropriate, no embedded text. | Approved |
| UI-020 | Preview well/header/footer/controls follow approved render, with honest state hierarchy. | Approved visual target |
| UI-021 | Responsive sizing and wrapping; no inaccessible actions, clipped categories, or destructive overlap. | Approved |
| UI-022 | Preserve meaningful item/class/state colors and recognizable artwork. | Approved |
| UI-023 | Reject charcoal/teal SaaS styling, bright gold perimeters, heavy filigree, particles, unnecessary glow, continuous animation, excessive prose. | Approved |
| UI-024 | Existing guild-bank style is a historical material/craftsmanship baseline, not a required missing mockup or substitute Reminders layout. | Approved clarification |
| UI-025 | No flattened screenshot substituted for working UI; assets must support real controls and scalable composition. | Approved |

Historical materials describe the same restrained leather/bronze identity and explicitly reject doubled outlines, heavy frames, broad olive/yellow primary fills, and copied branding/artwork. [pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws](https://pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws.com/projectfiles-prod/gateway-object-store/repos/files-9f57862b6fe94fc8323efb4e517c6350/downloads/5921924e0ff7ca967b97cdced03a147fdb8df8c2/PROJECT_BRIEF.md?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Checksum-Mode=ENABLED&X-Amz-Credential=ASIA2F3EMEYEVX5UQXVL%2F20261110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261110T225642Z&X-Amz-Expires=600&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEHoaCXVzLWVhc3QtMSJHMEUCIQCeQrPEVwzWT0mSL%2FNDfM6hm%2BBrnQ0jTjiqeqiFA00DBgIgH0SF8qdP0E8WME%2Fwk4DcXN%2Bl%2Bpzqs7XZfTzIazyEcv0qpwUIQhABGgw2OTk3NTMzMDk3MDUiDJzmk2TCR4ZUSu3GLCqEBRW3JAINlPHWqjH7pTzW%2BnwW4x5xN4RJf2%2F4Yc0940J%2BwWUZkhqdUk1ZQQW%2FiItN3i9ZkOSvV%2F%2FLiKPgQ%2BUx2HTafpmpWcsK6lKrCF0l%2Binn9S1w%2FK%2F%2BaP039kqcZZozY0xL3ZM8xd7%2BjTMO9bsiqL1GFNMXEpNuRRAGB0JjhaR0FYEzRwKlDFe0pahVJh8TWLQBY%2BZwh83%2BdGLkH618XRcBipzGT%2Bgj3WUEXpPAkgLxVyIumkckynbB%2Fd3RPbnU%2BNICj87ywLIb25dIYMsDblfamfHkR1gfkqmoe2Cjv0kMrLC3t75KnL54WcIat4h3bvAaWuPNbSO2ylzmGXcJIoaRkx0N9TqCHLML6YNLr91ucRMPzrZ2Q0tvOAPzoQ5aE%2Btx3eqQ3kTbY2fsG%2FCfWVTr3Z5wpKcAeG6OJvRFsZMSN32PGwmCxjK5xQifMtJP1Qqg3O%2FgHupKYBa83wnVJEtQnaJMpfJWL%2F%2BXgqaReNA8Eq7QOI4AYBUW0g2YvEYWjUA%2B%2FTGn%2B%2Fv4J1DE0rkZ%2FpIeK%2BC6fRpO6uciWGXikVo3osEbwIIqIpfm6TREVSyuXlUmeCFyKexnn2zaf53UT%2BAM8EbqmCqZ%2BtVQsVYwt0L9QIn%2BT19gOY4NJrOGkpg4sMJn5AmkiRVB8oxrw4hcMjqRWa6UJqC33dD5SIZLPBeo0BThObKFY3LCjbBw62AjAXzDDEDkT6%2F5Px6u8%2BbFX%2BWtVcmPh2FGEPysUG2%2Fw56CrkKZNhglJRaymwMM2e118BUmbN3an9UgUcS7fPSqxhLey92DpsYIhwls6jmqeJjzGM6eeDrHyE7xdYaY%2BB8i5lZdWwXPNyG7gbVpBmWdBrxI3elHMMGlzdcGOpABquFj3FoWrWroNbCBvXEgc7Jkzh%2Bd4T%2FKZLzX8tQfaFwr5Pe6VdyoRX0BDBYqPul76R83lCXQonEzzWymQeZ5t2q7uEJCuKMnBVow%2BrorsDyq%2Bka%2BPvV58JSbaKwqqb221kwKsJdUQ1KrHRZqfGjq%2BUmwWzNS3%2Fru30KS9eJ3Z2%2BXH3USXEZDDcy4xniP3ras&X-Amz-SignedHeaders=host&response-content-type=text%2Fmarkdown%3B%20charset%3Dutf-8&x-id=GetObject&X-Amz-Signature=69527b4f8f0b018b78b31725ae9f427165691beb95d7eb7429e91e70a5b01da0)

***

## 5. Mockup and Asset Inventory

| Asset ID | Asset | Role, authority, and availability |
|---|---|---|
| A-01 | `REMINDERS_PREVIEW` / visible `REMINDERS_PREVIEW.jpg` | Primary approved editor/preview target. Latest attachment shows list, pill switches, rounded fields/buttons, preview, Actual size/Fit, visibility explanation. Manually attach.  [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/e8fa01b3-c03e-4937-820d-9492ca1f4158/REMINDERS_PREVIEW.jpg) |
| A-02 | `REMINDERS_TEMPLATE_CATALOG` | Approved catalog target. Actual local filename/path must come from repository brief. Earlier visible image has four illustrative cards and Custom. Manually attach. |
| A-03 | `REMINDERS_WHEN_BUILDER` | User identifies as approved builder target. Exact image not visible in accessible excerpt; do not reconstruct from assumptions. Manually attach. |
| A-04 | Catalog image uploaded at 1:13 PM, attachment `272CC864-6D8D-40F5-A709-F50E88A8227F.jpeg` | Visible approved catalog composition: search, categories, cards, custom row, attached settings. Whether byte-identical to A-02 is unknown.  [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/a8acb655-63c8-414f-ae7b-d6e4e5a027a3/272CC864-6D8D-40F5-A709-F50E88A8227F.jpeg) |
| A-05 | Current When client screenshot, 3:53 PM | Rejected implementation evidence: picker overflow, existing controls/composition. Not a target. Manually attach.  [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/95709f3d-afdb-4b44-9684-bb989693740f/image.jpg) |
| A-06 | Current preview/editor client screenshot, 3:53 PM | Rejected implementation evidence for toggles, hierarchy, selection, layout. Manually attach.  [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/8d3ae29a-8bba-4d5a-b937-58f3629c9c86/image.jpg) |
| A-07 | Earlier client screenshots, 1:21 PM | Before-state: original long page, basic catalog, old inline preview. Useful history, not required target.  [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/190ee62e-df79-49dd-83c3-be3798981d3f/image.jpg) |
| A-08 | `TWICHUI_APPROVED_STYLE_2026-10-31.png` | Historical approved guild-bank implementation screenshot/material baseline. Not a separately required generated mockup. Available project file; attach only if useful. |
| A-09 | `REMINDERS-V2-MOCKUP.jpg` | Listed project attachment; contents/authority not reviewed here. Do not treat as authoritative without comparison to A-01–A-03. |
| A-10 | Style-v2 materials, `media/style-v2/` | Existing runtime reuse candidates, reported by Claude. Need repository inspection. |
| A-11 | `media/guildbank/` / `FrameLook.lua` | Existing frame implementation/assets. Reuse candidates, not design authority. |
| A-12 | Generated amber oil vial | Capability test succeeded; later reportedly reused. Actual path unknown here. |
| A-13 | Generated leather gauntlet | Codex reports one generation call. Approval as final art not independently established. |
| A-14 | Existing scroll, shield, arrows, food plate | Reported reused catalog art. Exact files need inspection. |
| A-15 | Codex simulator artifacts | Reported `editor.png`, `catalog.png`, `when.png`, `narrow.png`; not inspected here. |
| A-16 | `test-output/reminders-art-inspection/runtime-on-two-backgrounds.png` | Reported asset inspection composite, not accessed here. |

Reported simulator artifact directory:

```text
/home/rich/dev/personal/wow-ui-sim-lab/artifacts/reminders-20261110-154138/
```

These are local references, not public links.

The original catalog generation attempt in this assistant failed due to quota. The user then generated the accepted image elsewhere using a supplied prompt. That failed attempt is not an asset.

***

## 6. Screens and Interaction Flows

### 6.1 Main Reminders settings

Expected hierarchy:

1. Reminders title and master enable.
2. Reminder list and creation entry.
3. Selected reminder header/name/enable.
4. Appearance.
5. When summary and editor entry.
6. Sound.
7. Advanced.
8. Secondary diagnostics/help.
9. Profile/reset functions retained appropriately.

Exact placement of Duplicate/Delete should follow the reference where practical while preserving behavior. Their original location is not a semantic constraint.

### 6.2 Appearance preview

- Title `Live preview`.
- Selected reminder name.
- Preview drawing.
- Clickable artwork/text.
- Sizing controls as resolved under FR-008.
- Live visibility explanation distinct from preview state.
- Preview/on-screen controls according to existing semantics.

Empty selection behavior is not specified; inspect existing implementation. Do not invent an onboarding wizard.

### 6.3 Template catalog

- Title `Create a reminder`.
- Subtitle `Start with a template. Make it yours.`
- Search/categories shown in mockup, but scope unresolved.
- Illustrated entries.
- `Use template`.
- Distinct Custom row.
- Quiet explanation that creation makes an editable copy and starts off.

Illustrative card wording from approved catalog:

- `Weapon enchant` — “Remember your oil, stone, or poison.”
- `Well Fed` — “Remember to eat before heading out.”
- `Missing shield` — “Check your off hand before you go.”
- `Ammunition` — “Keep your ranged weapon supplied.”
- `Custom reminder` — “Start with your own conditions.”

These do not authorize removing the fifth supported template.

### 6.4 When builder

- Dedicated companion.
- Character targeting separate from conditions.
- Understandable conditions/groups.
- Add-condition picker.
- Drag/drop affordances.
- Back/close controls accessible.
- Existing Done/Cancel behavior must be inspected: Codex reported per-condition Done/Cancel, but its exact transaction boundaries are not approved here.

### 6.5 Important journeys

**Create from template**

1. Select existing reminder.
2. Open catalog.
3. Browse supported entries.
4. Use template.
5. Canonical creation validates.
6. Success creates independent disabled reminder.
7. New reminder selected; catalog closes; editor/preview update.
8. Missing essential configuration is clearly identified.

**Cancel catalog**

1. Open catalog.
2. Esc/close/cancel.
3. No reminder created.
4. Same selection/configuration and appropriate companion restored.

**Navigate from preview**

1. Click image or words.
2. Reveal relevant editor section.
3. Highlight destination.
4. No configuration mutation until actual editing.

**Edit conditions**

1. Open When.
2. Inspect target/grouping.
3. Add/edit/rearrange conditions.
4. Preserve rule semantics.
5. Apply/cancel according to established editor contract.
6. Return to appearance.

**Failure**

- At limit or incompatible profile: no partial creation, catalog remains open, reason visible.
- Invalid required input: no misleading active reminder.
- Invalid drag: no partial tree mutation.
- Narrow layout: accessible fallback, not clipped controls.

No loading-state requirement was established for these synchronous UI flows.

***

## 7. Data, Configuration, and Persistence

### Known requirements

- Preserve existing saved-data schema unless a justified change is necessary.
- Preserve profile sharing and compatibility.
- Template instances are independent deep copies.
- Each new reminder has unique identity.
- New template copies start disabled.
- Template definitions are not overwritten by player edits.
- Later catalog updates do not overwrite existing copies.
- Preview navigation does not save.
- Preview fitting must not silently change actual reminder scale.
- Preserve rule-tree semantics, identity, negation, and unknown states.
- Preserve existing import/export behavior if present.

### Unknown implementation details

- Exact reminder schema.
- Identity allocation.
- Schema version fields.
- SavedVariables keys.
- Import/export format.
- Selection persistence across reload.
- Whether preview preferences persist.
- Current undo/cancel transaction model.
- Whether any migration is needed for this revision.

The historical simulator tests do not prove disk persistence or reload behavior. Closing/reopening an in-memory frame is not persistence testing. [pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws](https://pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws.com/projectfiles-prod/gateway-object-store/repos/files-9f57862b6fe94fc8323efb4e517c6350/downloads/5921924e0ff7ca967b97cdced03a147fdb8df8c2/simulator-lab.md?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Checksum-Mode=ENABLED&X-Amz-Credential=ASIA2F3EMEYEVX5UQXVL%2F20261110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261110T225642Z&X-Amz-Expires=600&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEHoaCXVzLWVhc3QtMSJHMEUCIQCeQrPEVwzWT0mSL%2FNDfM6hm%2BBrnQ0jTjiqeqiFA00DBgIgH0SF8qdP0E8WME%2Fwk4DcXN%2Bl%2Bpzqs7XZfTzIazyEcv0qpwUIQhABGgw2OTk3NTMzMDk3MDUiDJzmk2TCR4ZUSu3GLCqEBRW3JAINlPHWqjH7pTzW%2BnwW4x5xN4RJf2%2F4Yc0940J%2BwWUZkhqdUk1ZQQW%2FiItN3i9ZkOSvV%2F%2FLiKPgQ%2BUx2HTafpmpWcsK6lKrCF0l%2Binn9S1w%2FK%2F%2BaP039kqcZZozY0xL3ZM8xd7%2BjTMO9bsiqL1GFNMXEpNuRRAGB0JjhaR0FYEzRwKlDFe0pahVJh8TWLQBY%2BZwh83%2BdGLkH618XRcBipzGT%2Bgj3WUEXpPAkgLxVyIumkckynbB%2Fd3RPbnU%2BNICj87ywLIb25dIYMsDblfamfHkR1gfkqmoe2Cjv0kMrLC3t75KnL54WcIat4h3bvAaWuPNbSO2ylzmGXcJIoaRkx0N9TqCHLML6YNLr91ucRMPzrZ2Q0tvOAPzoQ5aE%2Btx3eqQ3kTbY2fsG%2FCfWVTr3Z5wpKcAeG6OJvRFsZMSN32PGwmCxjK5xQifMtJP1Qqg3O%2FgHupKYBa83wnVJEtQnaJMpfJWL%2F%2BXgqaReNA8Eq7QOI4AYBUW0g2YvEYWjUA%2B%2FTGn%2B%2Fv4J1DE0rkZ%2FpIeK%2BC6fRpO6uciWGXikVo3osEbwIIqIpfm6TREVSyuXlUmeCFyKexnn2zaf53UT%2BAM8EbqmCqZ%2BtVQsVYwt0L9QIn%2BT19gOY4NJrOGkpg4sMJn5AmkiRVB8oxrw4hcMjqRWa6UJqC33dD5SIZLPBeo0BThObKFY3LCjbBw62AjAXzDDEDkT6%2F5Px6u8%2BbFX%2BWtVcmPh2FGEPysUG2%2Fw56CrkKZNhglJRaymwMM2e118BUmbN3an9UgUcS7fPSqxhLey92DpsYIhwls6jmqeJjzGM6eeDrHyE7xdYaY%2BB8i5lZdWwXPNyG7gbVpBmWdBrxI3elHMMGlzdcGOpABquFj3FoWrWroNbCBvXEgc7Jkzh%2Bd4T%2FKZLzX8tQfaFwr5Pe6VdyoRX0BDBYqPul76R83lCXQonEzzWymQeZ5t2q7uEJCuKMnBVow%2BrorsDyq%2Bka%2BPvV58JSbaKwqqb221kwKsJdUQ1KrHRZqfGjq%2BUmwWzNS3%2Fru30KS9eJ3Z2%2BXH3USXEZDDcy4xniP3ras&X-Amz-SignedHeaders=host&response-content-type=text%2Fmarkdown%3B%20charset%3Dutf-8&x-id=GetObject&X-Amz-Signature=af591c668db0508b96d87d60f73547b59d4aaf0dc10e5d30418256e47769ed32)

No linked-template synchronization, template-sharing/import system, or mandatory wizard was requested for the initial catalog.

***

## 8. Technical Constraints and Integration

### Runtime and architecture

- WoW Forever addon.
- Lua; syntax verification has used `luac5.1 -p`.
- Existing WoW frames and addon UI systems.
- Real TOCs/load ordering must be maintained.
- Existing renderer and rule model should be reused.
- No specific new external framework was approved.

### Shared-component safety

Changing a shared helper requires inspection of affected callers. This is targeted dependency inspection, not permission for an addon-wide investigation.

Where needed, use opt-in presentation so unrelated pages are not unintentionally restyled.

### Assets

- Respect current supported texture formats and loading conventions.
- Verify dimensions, alpha, slicing, texture coordinates, and packaging.
- Source/reference images are not runtime UI backgrounds by default.
- Do not invent a required format before inspecting current code.
- Preserve source artwork separately according to repository conventions.
- Exclude development references/source artifacts from release packages as appropriate.

### Image generation

- A generation-and-save test succeeded in the user’s Codex environment.
- Use that working path.
- Do not assume API fallback is necessary.
- No authorization to change credentials, buy credits, or switch to separately billed generation.
- No hard-coded provider/model dependency required in project files.

### Simulator environment: historical facts

The lab documentation describes:

- `wow-ui-sim v0.1.37`.
- Forever Linux x86-64 build.
- External lab `../wow-ui-sim-lab`.
- `bwrap` isolation, software rendering, read-only game access, no network.
- Real addon code loaded from a staged working tree.
- Custom addon-font substitution limitations. [pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws](https://pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws.com/projectfiles-prod/gateway-object-store/repos/files-9f57862b6fe94fc8323efb4e517c6350/downloads/5921924e0ff7ca967b97cdced03a147fdb8df8c2/simulator-lab.md?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Checksum-Mode=ENABLED&X-Amz-Credential=ASIA2F3EMEYEVX5UQXVL%2F20261110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261110T225642Z&X-Amz-Expires=600&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEHoaCXVzLWVhc3QtMSJHMEUCIQCeQrPEVwzWT0mSL%2FNDfM6hm%2BBrnQ0jTjiqeqiFA00DBgIgH0SF8qdP0E8WME%2Fwk4DcXN%2Bl%2Bpzqs7XZfTzIazyEcv0qpwUIQhABGgw2OTk3NTMzMDk3MDUiDJzmk2TCR4ZUSu3GLCqEBRW3JAINlPHWqjH7pTzW%2BnwW4x5xN4RJf2%2F4Yc0940J%2BwWUZkhqdUk1ZQQW%2FiItN3i9ZkOSvV%2F%2FLiKPgQ%2BUx2HTafpmpWcsK6lKrCF0l%2Binn9S1w%2FK%2F%2BaP039kqcZZozY0xL3ZM8xd7%2BjTMO9bsiqL1GFNMXEpNuRRAGB0JjhaR0FYEzRwKlDFe0pahVJh8TWLQBY%2BZwh83%2BdGLkH618XRcBipzGT%2Bgj3WUEXpPAkgLxVyIumkckynbB%2Fd3RPbnU%2BNICj87ywLIb25dIYMsDblfamfHkR1gfkqmoe2Cjv0kMrLC3t75KnL54WcIat4h3bvAaWuPNbSO2ylzmGXcJIoaRkx0N9TqCHLML6YNLr91ucRMPzrZ2Q0tvOAPzoQ5aE%2Btx3eqQ3kTbY2fsG%2FCfWVTr3Z5wpKcAeG6OJvRFsZMSN32PGwmCxjK5xQifMtJP1Qqg3O%2FgHupKYBa83wnVJEtQnaJMpfJWL%2F%2BXgqaReNA8Eq7QOI4AYBUW0g2YvEYWjUA%2B%2FTGn%2B%2Fv4J1DE0rkZ%2FpIeK%2BC6fRpO6uciWGXikVo3osEbwIIqIpfm6TREVSyuXlUmeCFyKexnn2zaf53UT%2BAM8EbqmCqZ%2BtVQsVYwt0L9QIn%2BT19gOY4NJrOGkpg4sMJn5AmkiRVB8oxrw4hcMjqRWa6UJqC33dD5SIZLPBeo0BThObKFY3LCjbBw62AjAXzDDEDkT6%2F5Px6u8%2BbFX%2BWtVcmPh2FGEPysUG2%2Fw56CrkKZNhglJRaymwMM2e118BUmbN3an9UgUcS7fPSqxhLey92DpsYIhwls6jmqeJjzGM6eeDrHyE7xdYaY%2BB8i5lZdWwXPNyG7gbVpBmWdBrxI3elHMMGlzdcGOpABquFj3FoWrWroNbCBvXEgc7Jkzh%2Bd4T%2FKZLzX8tQfaFwr5Pe6VdyoRX0BDBYqPul76R83lCXQonEzzWymQeZ5t2q7uEJCuKMnBVow%2BrorsDyq%2Bka%2BPvV58JSbaKwqqb221kwKsJdUQ1KrHRZqfGjq%2BUmwWzNS3%2Fru30KS9eJ3Z2%2BXH3USXEZDDcy4xniP3ras&X-Amz-SignedHeaders=host&response-content-type=text%2Fmarkdown%3B%20charset%3Dutf-8&x-id=GetObject&X-Amz-Signature=af591c668db0508b96d87d60f73547b59d4aaf0dc10e5d30418256e47769ed32)

Current pins and paths must be checked rather than assumed.

### Performance

No numeric frame-time or memory budget was established. Preserve bounded lifecycle behavior, avoid duplicate frames/listeners, and do not introduce unnecessary idle loops or continuous animation.

***

## 9. Decisions and Revisions History

| Previous approach | Revised/final position | Approval confidence |
|---|---|---|
| Individual per-template buttons | Illustrated catalog from New | High: user-approved mockup and implementation direction |
| Inline preview far down page | Attached companion | High; user confirmed working |
| Live-updating display only | Also click artwork/text to locate settings | High |
| Milestone-one execution stop | End-to-end execution, phases internal only | High: explicit user correction |
| Historical drag/drop optional | Drag/drop required | High: explicit user complaint that it is missing |
| Reuse existing controls interpreted conservatively | Achieve approved controls/materials, extending helpers as needed | High for desired outcome |
| “Implemented” based on tests/screenshots | Visual acceptance withheld because real result differs | High: explicit rejection |
| Bespoke artwork deferred | Working image generation may produce needed assets | High |
| Guild-bank mockup requested as missing prerequisite | Only three Reminders renders required | High: explicit clarification |
| Catalog/preview believed uncommitted | Claude later found commit `2e0c5fe5` | Reported inspection, current state unknown |
| When builder assumed future from scratch | Existing inline designer must be reused/adapted | Reported code finding |
| Search/categories deferred | Assistant later proposed inclusion | Unresolved; do not silently settle |
| Actual size/Fit implicit in render | Assistant later explicitly requested implementation | Visual target clear; functional default unresolved |

### Approaches that should not reappear

- Stopping automatically after each implementation phase.
- Treating mockups as loose color inspiration.
- Declaring success because all frames construct.
- Claiming visual verification without inspecting images.
- Asking for a nonexistent guild-bank mockup.
- Rebuilding renderer/rule engine unnecessarily.
- Using screenshot textures as flattened interactive interfaces.
- Repairing simulator internals to excuse production UI differences.

***

## 10. Dependencies and Suggested Implementation Order

This is dependency analysis, not a final implementation plan.

### Foundations

- Reconcile current code, brief, references, and rejected result.
- Establish local visual tokens/components for controls, text, frames, selection.
- Identify shared-helper consumers before changes.
- Establish screenshot scenarios that show the three target surfaces.

### Dependent groups

1. Editor composition and list selection depend on styling foundations.
2. Preview interaction depends on reveal/highlight integration and correct hit regions.
3. Catalog polish depends on cards, artwork, controls, and accessible sizing.
4. When polish and drag/drop depend on existing rule-tree/editor contracts.
5. Companion transitions depend on all three surfaces and placement.
6. Final comparison depends on actual integrated screenshots, not isolated controls.

### Potential conflicts

- Existing immediate-save behavior versus Done/Cancel drafts.
- Switch visuals versus existing checkbox event plumbing.
- Actual-size preview versus automatic fitting.
- Fixed side panel versus insufficient screen width.
- Shared styling versus unrelated pages.
- Drag/drop tree movement versus stable identity/validation.
- Simulator font substitution versus real-client text fit.

Implementation may proceed through these groups without user approval at every phase.

***

## 11. Testing and Acceptance Criteria

### Functional mapping

| Test area | Requirements |
|---|---|
| List/editor/preview synchronization | FR-001–FR-005 |
| Enable semantics and silent preview | FR-003, FR-006 |
| On-screen cleanup | FR-007, FR-022 |
| Catalog creation/cancel/refusal | FR-010–FR-015 |
| Filtering, if authorized | FR-016 |
| When grouping and semantic preservation | FR-017–FR-021 |
| Placement and scaling | FR-023, UI-021 |
| Existing functionality regression | FR-024 |
| Asset and packaging checks | FR-025, UI-019, UI-025 |
| Evidence/reporting | FR-026–FR-028 |

### Visual acceptance

Compare actual captures against A-01–A-03 for:

- Composition and relative proportions.
- Pill switches.
- Button/dropdown/field/tab treatment.
- Selected reminder/navigation states.
- Text sizes, colors, hierarchy.
- Frame weight/materials.
- Card artwork proportions.
- Preview controls/status layout.
- Wrapping, clipping, overflow.
- Normal and constrained supported layouts.

The observed clipped When categories must fail acceptance. [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/137250785/95709f3d-afdb-4b44-9684-bb989693740f/image.jpg)

No numeric image-similarity threshold was established. Pixel identity is not required where actual content/aspect ratio differs, but major legacy styling is not an acceptable adaptation.

### Reported commands

```bash
./tests/run.sh
luac5.1 -p <edited-or-new-files>
git diff --check
bash tools/simlab/reminders.sh
SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh
```

The first three and the Reminders-specific simulator command are reported by Codex. Inspect scripts and repository policy before rerunning.

Historical commands include `tools/simlab/interact.sh` and `tools/simlab/diagnose.sh`, but they should not be run indiscriminately. The latter is for messaging/group/timer diagnostics, not routine visual revision. [pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws](https://pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws.com/projectfiles-prod/gateway-object-store/repos/files-9f57862b6fe94fc8323efb4e517c6350/downloads/5921924e0ff7ca967b97cdced03a147fdb8df8c2/simulator-lab.md?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Checksum-Mode=ENABLED&X-Amz-Credential=ASIA2F3EMEYEVX5UQXVL%2F20261110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261110T225642Z&X-Amz-Expires=600&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEHoaCXVzLWVhc3QtMSJHMEUCIQCeQrPEVwzWT0mSL%2FNDfM6hm%2BBrnQ0jTjiqeqiFA00DBgIgH0SF8qdP0E8WME%2Fwk4DcXN%2Bl%2Bpzqs7XZfTzIazyEcv0qpwUIQhABGgw2OTk3NTMzMDk3MDUiDJzmk2TCR4ZUSu3GLCqEBRW3JAINlPHWqjH7pTzW%2BnwW4x5xN4RJf2%2F4Yc0940J%2BwWUZkhqdUk1ZQQW%2FiItN3i9ZkOSvV%2F%2FLiKPgQ%2BUx2HTafpmpWcsK6lKrCF0l%2Binn9S1w%2FK%2F%2BaP039kqcZZozY0xL3ZM8xd7%2BjTMO9bsiqL1GFNMXEpNuRRAGB0JjhaR0FYEzRwKlDFe0pahVJh8TWLQBY%2BZwh83%2BdGLkH618XRcBipzGT%2Bgj3WUEXpPAkgLxVyIumkckynbB%2Fd3RPbnU%2BNICj87ywLIb25dIYMsDblfamfHkR1gfkqmoe2Cjv0kMrLC3t75KnL54WcIat4h3bvAaWuPNbSO2ylzmGXcJIoaRkx0N9TqCHLML6YNLr91ucRMPzrZ2Q0tvOAPzoQ5aE%2Btx3eqQ3kTbY2fsG%2FCfWVTr3Z5wpKcAeG6OJvRFsZMSN32PGwmCxjK5xQifMtJP1Qqg3O%2FgHupKYBa83wnVJEtQnaJMpfJWL%2F%2BXgqaReNA8Eq7QOI4AYBUW0g2YvEYWjUA%2B%2FTGn%2B%2Fv4J1DE0rkZ%2FpIeK%2BC6fRpO6uciWGXikVo3osEbwIIqIpfm6TREVSyuXlUmeCFyKexnn2zaf53UT%2BAM8EbqmCqZ%2BtVQsVYwt0L9QIn%2BT19gOY4NJrOGkpg4sMJn5AmkiRVB8oxrw4hcMjqRWa6UJqC33dD5SIZLPBeo0BThObKFY3LCjbBw62AjAXzDDEDkT6%2F5Px6u8%2BbFX%2BWtVcmPh2FGEPysUG2%2Fw56CrkKZNhglJRaymwMM2e118BUmbN3an9UgUcS7fPSqxhLey92DpsYIhwls6jmqeJjzGM6eeDrHyE7xdYaY%2BB8i5lZdWwXPNyG7gbVpBmWdBrxI3elHMMGlzdcGOpABquFj3FoWrWroNbCBvXEgc7Jkzh%2Bd4T%2FKZLzX8tQfaFwr5Pe6VdyoRX0BDBYqPul76R83lCXQonEzzWymQeZ5t2q7uEJCuKMnBVow%2BrorsDyq%2Bka%2BPvV58JSbaKwqqb221kwKsJdUQ1KrHRZqfGjq%2BUmwWzNS3%2Fru30KS9eJ3Z2%2BXH3USXEZDDcy4xniP3ras&X-Amz-SignedHeaders=host&response-content-type=text%2Fmarkdown%3B%20charset%3Dutf-8&x-id=GetObject&X-Amz-Signature=af591c668db0508b96d87d60f73547b59d4aaf0dc10e5d30418256e47769ed32)

### Evidence boundaries

- Unit tests prove only covered logic.
- Handler simulations do not prove real pointer hit testing.
- Construction is not full interaction coverage.
- Screenshots existing is not visual acceptance.
- Simulator fonts may differ from actual fonts.
- Persistence, combat/taint, real input, packaged install, and addon integration require separate evidence. [pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws](https://pplxfilegitgateway-projectfiles-prod-use1.s3.us-east-1.amazonaws.com/projectfiles-prod/gateway-object-store/repos/files-9f57862b6fe94fc8323efb4e517c6350/downloads/5921924e0ff7ca967b97cdced03a147fdb8df8c2/simulator-lab.md?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Checksum-Mode=ENABLED&X-Amz-Credential=ASIA2F3EMEYEVX5UQXVL%2F20261110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261110T225642Z&X-Amz-Expires=600&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEHoaCXVzLWVhc3QtMSJHMEUCIQCeQrPEVwzWT0mSL%2FNDfM6hm%2BBrnQ0jTjiqeqiFA00DBgIgH0SF8qdP0E8WME%2Fwk4DcXN%2Bl%2Bpzqs7XZfTzIazyEcv0qpwUIQhABGgw2OTk3NTMzMDk3MDUiDJzmk2TCR4ZUSu3GLCqEBRW3JAINlPHWqjH7pTzW%2BnwW4x5xN4RJf2%2F4Yc0940J%2BwWUZkhqdUk1ZQQW%2FiItN3i9ZkOSvV%2F%2FLiKPgQ%2BUx2HTafpmpWcsK6lKrCF0l%2Binn9S1w%2FK%2F%2BaP039kqcZZozY0xL3ZM8xd7%2BjTMO9bsiqL1GFNMXEpNuRRAGB0JjhaR0FYEzRwKlDFe0pahVJh8TWLQBY%2BZwh83%2BdGLkH618XRcBipzGT%2Bgj3WUEXpPAkgLxVyIumkckynbB%2Fd3RPbnU%2BNICj87ywLIb25dIYMsDblfamfHkR1gfkqmoe2Cjv0kMrLC3t75KnL54WcIat4h3bvAaWuPNbSO2ylzmGXcJIoaRkx0N9TqCHLML6YNLr91ucRMPzrZ2Q0tvOAPzoQ5aE%2Btx3eqQ3kTbY2fsG%2FCfWVTr3Z5wpKcAeG6OJvRFsZMSN32PGwmCxjK5xQifMtJP1Qqg3O%2FgHupKYBa83wnVJEtQnaJMpfJWL%2F%2BXgqaReNA8Eq7QOI4AYBUW0g2YvEYWjUA%2B%2FTGn%2B%2Fv4J1DE0rkZ%2FpIeK%2BC6fRpO6uciWGXikVo3osEbwIIqIpfm6TREVSyuXlUmeCFyKexnn2zaf53UT%2BAM8EbqmCqZ%2BtVQsVYwt0L9QIn%2BT19gOY4NJrOGkpg4sMJn5AmkiRVB8oxrw4hcMjqRWa6UJqC33dD5SIZLPBeo0BThObKFY3LCjbBw62AjAXzDDEDkT6%2F5Px6u8%2BbFX%2BWtVcmPh2FGEPysUG2%2Fw56CrkKZNhglJRaymwMM2e118BUmbN3an9UgUcS7fPSqxhLey92DpsYIhwls6jmqeJjzGM6eeDrHyE7xdYaY%2BB8i5lZdWwXPNyG7gbVpBmWdBrxI3elHMMGlzdcGOpABquFj3FoWrWroNbCBvXEgc7Jkzh%2Bd4T%2FKZLzX8tQfaFwr5Pe6VdyoRX0BDBYqPul76R83lCXQonEzzWymQeZ5t2q7uEJCuKMnBVow%2BrorsDyq%2Bka%2BPvV58JSbaKwqqb221kwKsJdUQ1KrHRZqfGjq%2BUmwWzNS3%2Fru30KS9eJ3Z2%2BXH3USXEZDDcy4xniP3ras&X-Amz-SignedHeaders=host&response-content-type=text%2Fmarkdown%3B%20charset%3Dutf-8&x-id=GetObject&X-Amz-Signature=af591c668db0508b96d87d60f73547b59d4aaf0dc10e5d30418256e47769ed32)

### Real-client checks

- Preview artwork/text click targets at normal/higher scale.
- Switches and dropdown interactions.
- Long names and real font wrapping.
- Esc/Back/cancel across companions.
- Drag/drop with actual pointer.
- Disabled preview remains disabled/silent.
- Cleanup on leaving/closing.
- Reload persistence.
- Narrow placement.
- Missing-input behavior.
- Active reminder versus temporary preview distinction.

***

## 12. Unknowns, Conflicts, and Open Questions

### Must resolve before implementing the affected behavior

1. Search/category scope: approved visual presence but repeated functional deferral; C13 inclusion was assistant-proposed.
2. Exact drag/drop scope: condition moves definitely required; group dragging/nesting/drop rules need reference/code reconciliation.
3. Actual size/Fit default and persistence: mockup shows modes, but defaults not established.
4. Current visual-reference files: actual paths must be confirmed and images opened.
5. Current working-tree ownership: ensure no simultaneous Claude/Codex edits.

These do not necessarily block independent styling work.

### Can resolve during codebase inspection

- Exact save schema and setters.
- Existing draft/cancel semantics.
- Current incomplete-item validation.
- Existing nesting restrictions.
- Current actual-size/fit implementation.
- Current visibility explanation API.
- Shared control callers.
- Asset loading formats and conversion tools.
- Current branch/diff/commit state.
- Scope of modified navigation styling.
- Whether companion minimization preserves state.
- Required final tests.

### Can safely defer

- Unspecified new condition types.
- Full addon-wide rollout.
- Template synchronization/sharing systems.
- Broad import/export redesign.
- Simulator font-engine fixes.
- General architecture/performance audits.
- Other addon backlog features.

### Important missing evidence

- Actual When-builder target image in this handoff context.
- Current local brief and instructions.
- Current implementation diff.
- Codex simulator captures.
- Drag/drop runtime evidence.
- Fresh persistence and real-client acceptance.

### No unnecessary reopening

Do not ask whether the user wants:

- Closer visual matching.
- Toggles instead of rejected checkboxes.
- Interactive preview navigation.
- Drag-and-drop.
- Simulator image comparison.
- End-to-end execution without routine phase gates.

Those directions are established.

***

## 13. Implementation Handoff Summary

### Consolidated approved functional scope

- FR-001–FR-007: compact editor, selection, switches, attached interactive isolated preview.
- FR-009–FR-015: honest state, catalog, independent disabled copies, safe validation/refusals, Custom.
- FR-017–FR-020: attached understandable When editor, preserved semantics, drag/drop.
- FR-022–FR-028: lifecycle, accessible placement, behavior preservation, assets, simulator iteration, end-to-end execution, honest evidence.

Conditional/unresolved:

- FR-008: sizing-mode functional specifics/default.
- FR-016: search/category scope.
- FR-021: detailed drag implementation safety/alternatives specification.

### Consolidated approved visual scope

UI-001–UI-025 define the target visual direction. UI-016’s global adoption extent remains limited by the explicit no-addon-wide-rollout rule.

### Authoritative references

1. A-01 `REMINDERS_PREVIEW`.
2. A-02 `REMINDERS_TEMPLATE_CATALOG`.
3. A-03 `REMINDERS_WHEN_BUILDER`.

A-05/A-06 demonstrate rejected output. A-08 is historical material guidance, not a missing prerequisite.

### Behaviors that must not change

- Rule semantics and unknown handling.
- Existing player configuration.
- Profile compatibility.
- Independent template copies.
- Disabled new drafts.
- Creation limits/refusals.
- Silent isolated previews.
- Explicit on-screen preview control.
- Existing naming/duplicate/delete/sound/advanced/test capabilities.
- No unexpected live game actions.

### Known implementation risks

- Passing tests masking a visually incomplete result.
- Misreading optional/deferred scope.
- Control skinning without event correctness.
- Unclear drag transaction boundaries.
- Shared-component regressions.
- Incorrect status labels.
- Narrow-layout overflow.
- Simulator typography differences.
- Premature completion claims.

### Recommended first steps for the next coding agent

1. Read actual repository instructions and current brief.
2. Confirm `feature/style`, current diff, and ownership.
3. Open all three approved images.
4. Compare current actual UI and document concrete discrepancies in the existing brief.
5. Resolve only consequential scope conflicts.
6. Continue implementation rather than restart.
7. Render, inspect, compare, refine.
8. Report remaining gaps candidly.

### Definition of fully completed

The approved interactions work, existing semantics/data are preserved, the three surfaces closely follow their authoritative renders, obvious legacy controls/overflow are corrected, drag/drop is implemented and appropriately verified, assets are integrated correctly, required tests pass, simulator comparisons are actually inspected, and remaining real-client-only checks are clearly identified.

Functional implementation alone is not visual acceptance.

***

## 14. Traceability Matrix

| ID | Requirement | Status | Source/reference | Mockup | Acceptance | Dependencies |
|---|---|---|---|---|---|---|
| FR-001 | Compact editor | Approved | C8/C10/C12 | A-01 | Primary flow matches composition | UI-001–010 |
| FR-002 | Selection consistency | Approved | C10–12 | A-01 | List/editor/preview agree | FR-004 |
| FR-003 | Enable controls | Approved | C12 | A-01 | Switch semantics preserved | UI-011 |
| FR-004 | Attached preview | Approved | C4/C5 | A-01 | Updates beside editor | Renderer |
| FR-005 | Click-to-setting | Approved | C10 | A-01 | Reveal/highlight, no mutation | FR-004 |
| FR-006 | Isolated silent preview | Approved | C4/C10 | A-01 | Disabled stays off/silent | Renderer |
| FR-007 | On-screen preview | Approved | C4/C11 | A-01 | Explicit show/hide, cleanup | FR-022 |
| FR-008 | Actual size/Fit | Unresolved specifics | Render/C13 | A-01 | Real modes, no saved-scale mutation | FR-004 |
| FR-009 | Honest visibility | Approved principle | Render/designer | A-01 | States not conflated | FR-019 |
| FR-010 | Catalog open/cancel | Approved | C1/C2 | A-02 | No creation on cancel | FR-022 |
| FR-011 | Illustrated catalog | Approved | C1/C10 | A-02 | All cards accessible | UI-013 |
| FR-012 | Independent copies | Approved | C1/C2 | A-02 | Unique, deep-copy, off | Canonical creation |
| FR-013 | Limits/refusals | Approved | C2 | A-02 | No partial creation | FR-012 |
| FR-014 | Custom reminder | Approved | C1/C2 | A-02 | Existing flow preserved | FR-013 |
| FR-015 | Missing-input safety | Approved | C1/C10 | A-02 | Invalid enable prevented | Validation |
| FR-016 | Search/categories | Unresolved scope | C1/C10/C13 | A-02 | Correct filtering if included | Catalog metadata |
| FR-017 | When companion | Approved | C10 | A-03 | Existing designer integrated | FR-022 |
| FR-018 | Understandable grouping | Approved | Backlog/discussion | A-03 | Clear All/Any, targeting | FR-019 |
| FR-019 | Rule preservation | Approved | C10 | A-03 | Equivalent results/config | Rule model |
| FR-020 | Drag/drop | Approved | C12 | A-03 | Actual arrangement works | FR-019 |
| FR-021 | Safe drag mechanics | Proposed details | C13 | A-03 | Cancel/invalid no mutation | FR-020 |
| FR-022 | Companion lifecycle | Approved | C4/C10 | A-01–03 | Correct exclusive surface | All companions |
| FR-023 | Placement | Approved | C10/C12 | A-01–03 | No inaccessible controls | UI-021 |
| FR-024 | Preserve editor actions | Approved | C3/C10 | A-01 | All existing functions reachable | Existing API |
| FR-025 | Asset workflow | Approved | C9/C10 | A-01–03 | Usable verified runtime art | Asset conventions |
| FR-026 | Simulator iteration | Approved | C8/C12 | A-01–03 | Inspected comparisons | Simulator |
| FR-027 | End-to-end execution | Approved | C8/C10 | All | No routine phase stops | Safety boundaries |
| FR-028 | Honest reporting | Approved | C10/C12 | All | Evidence separated | All verification |
| UI-001 | Composition fidelity | Approved | C12 | A-01–03 | Not palette-only imitation | FR-026 |
| UI-002 | Leather/materials | Approved | Brief/renders | A-01–03 | Warm restrained surfaces | Assets |
| UI-003 | Palette | Approved | C12/renders | A-01–03 | Ivory/bronze hierarchy | UI-007 |
| UI-004 | Frames | Approved | Brief/renders | A-01–03 | Consistent corners/rails | Assets |
| UI-005 | Depth/bevel | Approved | Brief | A-01–03 | Subtle, behind text | UI-004 |
| UI-006 | Rounded controls | Approved | C12 | A-01–03 | Coherent corner treatment | Components |
| UI-007 | Typography | Approved | C12 | A-01–03 | Readable target hierarchy | Font inspection |
| UI-008 | Spacing/alignment | Approved | C12 | A-01–03 | No wrapping/clipping defects | Layout |
| UI-009 | List/editor proportions | Approved target | Render/C12 | A-01 | Substantial coherent list well | FR-001 |
| UI-010 | Secondary diagnostics | Approved | Brief/C10 | A-01 | Primary editing prioritized | FR-024 |
| UI-011 | Pill switches | Approved | C12 | A-01 | No rejected checkbox treatment | FR-003 |
| UI-012 | Beveled buttons | Approved | C12 | A-01–03 | Matches target control language | Components |
| UI-013 | Catalog cards | Approved | C1 | A-02 | Consistent illustrated cards | FR-011 |
| UI-014 | Tabs/fields/dropdowns | Approved | C12 | A-01–03 | Styled and non-overflowing | Layout |
| UI-015 | Selected states | Approved | C12 | A-01 | Rounded rich gold coherence | FR-002 |
| UI-016 | Navigation prominence | Approved direction | Earlier discussion | A-01 | Strong readable selection | Scope inspection |
| UI-017 | Interaction states | Approved | Brief | All | Clear usable states | Components |
| UI-018 | Preview affordances | Approved | Interactive discussion | A-01 | Discoverable restrained feedback | FR-005 |
| UI-019 | Artwork legibility | Approved | C9/C10 | A-02 | Clean at actual size | FR-025 |
| UI-020 | Preview hierarchy | Approved target | Render | A-01 | Header/well/footer coherent | FR-004/009 |
| UI-021 | Responsive layout | Approved | C12 | All | No clipped actions/categories | FR-023 |
| UI-022 | Meaningful colors/art | Approved | Brief | All | Existing meaning preserved | Existing assets |
| UI-023 | Rejected aesthetics | Approved | Brief/discussion | All | No dashboard/clutter drift | Visual review |
| UI-024 | Guild-bank reference role | Approved clarification | C7 | A-08 | No missing-mockup blocker | None |
| UI-025 | Real composited UI | Approved | C10 | All | No flattened UI screenshot | FR-025 |

***

## Materials to provide manually to ChatGPT

- [ ] `REMINDERS_PREVIEW`, `REMINDERS_TEMPLATE_CATALOG`, and `REMINDERS_WHEN_BUILDER` in their actual image files.
- [ ] Latest rejected real-client screenshots, especially the overflowing When picker and checkbox/button styling.
- [ ] Current `docs/reminders-style-upgrade.md`.
- [ ] Current `AGENTS.md`, applicable scoped instructions, and `CLAUDE.md`.
- [ ] Current `STATUS_AND_BACKLOG.md`.
- [ ] Current `feature/style` diff or repository access, including branch/commit state.
- [ ] Codex’s actual `editor.png`, `catalog.png`, `when.png`, and `narrow.png` captures.
- [ ] Generated/runtime asset paths and inspection composite if needed.
- [ ] Current simulator instructions and any new Reminders scenario files.

Do not require a separate guild-bank mockup. The three approved Reminders renders are the authoritative visual targets.