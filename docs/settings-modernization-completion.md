# Settings modernization: implementation completion

11 November 2026, `feature/style`. This report closes the implementation queue in the
[persistent matrix](settings-modernization-matrix.md), preserving the evidence in the second-pass, Batch 1–3,
Magic Inventory and Auction House reports. It does not establish real-client acceptance.

## Final changes

**World Map Places:** the original flat layer/appearance form is now an illustrated layer-selection card,
a separate readability group and a disclosed map-actions/coverage guide. The map's real status and a safe
Open map setup link explain the dependency without automatically enabling exploration or opening a map.
All six original preference keys, defaults, write APIs and reset semantics remain. Layer preferences can still
be prepared while exploration is off. Missing bundled data is explicitly Unavailable, not a zero-count assurance.
This page controls built-in places, not saved pins: Add/Edit/Delete/import/share remain in their existing map/pin
workflows, covered by existing map/pin tests. No new saved-place model or coordinate conversion was introduced.
The actual map is its preview; a fabricated map companion was deliberately omitted.

**Addon Skins:** the previous switch list now has compact per-addon cards with recognizable existing icons,
Use/Skip preference labels, visible installed/disabled/waiting/reload guidance, and retained native-look page links.
Availability is distinct from saved enablement. Enabled addon-loaded status deliberately does not claim verified
application. Restoring the normal appearance uses the existing off-plus-reload path; no external frames are
created, restyled or reset by opening this page. Auctionator's additional Ellesmere AH-skin requirement remains in
its help. SpeakStone and RestedXP retain their dedicated pages and native samples. Missing-addon controls stay
unavailable and preferences survive. No third-party addon was installed for verification.

**Visual refinement:** initial screenshots exposed repeated skin art, misleading On labels for missing integrations,
and hidden compact-card summaries. Distinct existing guide/scales/map/vendor art, Use/Skip labels and visible
status notes correct these. A subsequent review shortened repetitive implementation-facing notes to player actions.
Canonical walnut cards, bronze controls, shared sliders/disclosures and tooltips are reused. No new assets or
shared-component implementation changes were necessary. Completed Home/Reminders/Magic Inventory pages are unchanged.

No matrix row was Partially modernized at baseline; the only Styled-only rows were these two. The final matrix has
**58 Substantially modernized, 0 Partially modernized, 0 Styled only, 0 Verified, 0 Blocked**.
No named P0/P1 simulator-verifiable implementation defect was open in the matrix. Simulator/native scrollbar
end-stop discrepancies previously recorded for Auction House remain an acceptance gap; no simulator-engine patch
or speculative broad window rewrite is included. No other page was re-audited or promoted merely for shared style.

## Verification and reruns

New `tests/test_remaining_settings.lua` covers place binding/retention, navigation without enablement, skin
availability, pending reload and saved preference restoration. Existing map exploration/data/tools, skin/settings,
profile/default and lifecycle tests remain the deeper runtime evidence. The reviewed settings-contract fixture
changes only these two pages' section/row composition: 770 settings remain, all keys/defaults/write/reset results
unchanged. Lua 5.1 syntax and diff checks are required for edited files.

Permanent simulator scenarios extend `tools/simlab/scenarios/settings.lua`:

```sh
SIMLAB_SETTINGS_DATA='"on"' bash tools/simlab/settings.sh worldMapPlaces
SIMLAB_SETTINGS_DATA='"advanced"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh worldMapPlaces
SIMLAB_SETTINGS_DATA='"empty"' bash tools/simlab/settings.sh worldMapPlaces
SIMLAB_SETTINGS_INTEGRATION='"available"' bash tools/simlab/settings.sh skins
SIMLAB_SETTINGS_INTEGRATION='"absent"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh skins
# Lower launcher/scroll view: add SIMLAB_SETTINGS_DATA='"bottom"' to a skins command.
bash tools/simlab/settings.sh overview reminders magicInventory auction worldMapPlaces skins notifications healerWatch navigation chronicle
```

Fixtures use actual addon controls and deterministic availability, never third-party frame operations or real player
data. The initial dependency fixture failed because Kit had not yet loaded; it now explicitly loads the settings
addon before supplying status stand-ins. This is fixture setup, not simulator-engine modification.
All simulator input is handler-level. Fonts are substituted, API sources predate the installed client, and real
pointer delivery, combat/taint, reload persistence and applied third-party appearance are not established.
Settings remain lazy/cached in the existing load-on-demand addon; no new polling, events or runtime dependencies,
performance claim, diagnostic scope or data migration is introduced.

## Real-client acceptance queue

- **All pages:** shipped fonts/localization and large labels; mouse/keyboard, dropdowns, focus/Escape, tooltips,
  constrained scrolling/end-stops; page/reset scope, reload persistence and profile switching.
- **World map/pins/navigation:** real place positions/floors, layers and native map context actions; blocker addons,
  actual routes, safe combat deferral, saved coordinates/imports/sharing and no navigation from settings opening.
- **EllesmereUI integrations:** each of Attune, Auctionator, ForeverDungeonJournal and WhatsTraining installed,
  absent and disabled; EllesmereUI missing/disabled/skin support off; on/off/reload/revert, including Auctionator's
  AH skin prerequisite. Actual external-addon compatibility is not established by fixtures.
- **RestedXP/SpeakStone:** native sample, apply/restore, conflict behavior and reload, retaining saved preferences.
- **Auction/inventory/chat:** real item/channel data, protected-item and first-match behavior; explicit transfer/post
  review and confirmation, native drag/drop, keyboard entry and live mailbox totals.
- **Companions:** Home → Notifications → Healer Watch → Journey Chronicle → Navigation → other page, search/close,
  nested dialogs and gameplay transition; no leaked companion or duplicate event listeners, including combat.

There are no known implementation blockers from this scoped pass. Evidence below distinguishes construction/state
checks and screenshot review from native-client acceptance; only the latter can promote a page to Verified.

## Final evidence

**Unit-tested:** `./tests/run.sh` — **191 passed, 0 failed** during implementation. Final focused
`test_remaining_settings.lua` and `test_settings_contract.lua` reruns passed after refinements, as did Lua syntax
and `git diff --check`. The initial new unit assertion incorrectly assumed layer preferences were disabled while
the map was off; inspection confirmed the existing editable-preference contract and the test was corrected.
No default or runtime behavior was changed to satisfy that test.

**Simulator-tested / screenshot-reviewed:** local captures under `../wow-ui-sim-lab/artifacts/`, not committed or
packaged. Each listed image was opened; these are structural current-state captures, not approved golden baselines.

| Folder (`settings-20261111-…`) | File/view | Checks |
|---|---|---|
| `130603` | `worldMapPlaces.png`, `skins.png`: initial render, before status/icon corrections | 14 / 11 |
| `130655` | Enabled layer configuration | 16 |
| `130710` | Constrained Places, disclosure open | 16 |
| `130807` | Available skins fixture, all four preferences toggled/restored | 15 |
| `130823` | Absent skins, constrained view | 15 |
| `130856` | Home, empty Reminders/Magic Inventory, Auction House, Places and Skins | 22 / 11 / 20 / 17 / 16 / 11 |
| `131044` | Final constrained Places explanation, actual coverage counts | 17 |

The first representative cross-page command used the obsolete/nonexistent page key `arrival`; it stopped safely
at that selection. Its prior page results remain valid. The remaining four families were rerun using
`notifications`, `healerWatch`, `navigation` and `chronicle`. No addon change was needed for the command correction.

| Folder (`settings-20261111-…`) | Final additional screenshot review | Checks |
|---|---|---|
| `131100` | Missing bundled map data; Unavailable / No data | 17 |
| `131116` | Disabled skin preference fixture, lower launcher, existing reload prompt/footer; no reload invoked | 16 |
| `131131` | Notifications, Healer Watch, Navigation, Journey Chronicle with live samples | 29 / 39 / 21 / 21 |

Across these representative screens, headings, tabs, canonical section materials, dropdowns, disclosures and selected
navigation remain consistent. Existing companion scenarios exercise dismiss/reopen, search hiding and navigation
cleanup; actual pointer input and native tooltip placement still require the client. Historical populated Reminders
and Magic Inventory pose evidence remains in their own reports; their empty states were the fresh integration captures.

Final follow-up captures opened: `settings-20261111-131223/skins.png` (15 checks; shortened available-state notes)
and `settings-20261111-131238/navigation.png` (21 checks; constrained layout plus live companion). No significant
new structural discrepancy was found. All capture directories remain excluded from the Git checkpoint.
