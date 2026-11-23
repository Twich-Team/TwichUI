# Map Diagnostics

Open **`/tui mapdiag`**. The dedicated window uses TwichUI's existing framed
leather/walnut/bronze palette. The diagnostics addon loads on first use; it does
not add a second world map or alter `/tui diagnostics` or `/tui perf`.

## Player workflow

1. Open the world map and find the problem. Type `/tui mapdiag`.
2. For an issue currently visible, choose **Capture Snapshot**. For a transition
   or jump, choose **Start Recording**, move the window aside or close it,
   reproduce the issue, reopen it and choose **Mark Issue**.
3. Choose **Stop & Prepare Report**, or **Copy for AI**. The compact report is
   selected automatically; **press Ctrl+C**, then paste into ChatGPT/Codex.
4. **Select Again** reselects the existing prepared text without rebuilding it.
   For deeper investigation choose **Detailed Report**. Copy its numbered parts
   with **Next/Previous** if necessary. Send every part with its header intact.

Recordings stop after 90 seconds by default (engine accepts 15–180 seconds).
Closing the window does not discard or stop an active recording. Map close and
reopen are captured. Nothing records before you explicitly start, and no capture
survives reload/logout. Starting again replaces the previous session capture.
A snapshot/recording's optional description is user-provided untrusted text,
sanitized by the existing diagnostics redactor. Do not put private details in it.

The **view/cursor geometry** checkbox is off by default and takes effect for
the next capture/recording. Map IDs, texture IDs and technical tile indices are
always included; they can identify the viewed area. Player location is never
queried. Character/account/guild identifiers, chat, full SavedVariables, raw
error messages and raw stacks are excluded. Marker providers expose only
allowlisted counters. No upload, chat send, file write or clipboard write occurs.

## Clipboard and combat evidence

Forever's `OsDocumentation.lua` documents `CopyToClipboard` with restrictions
and `SecretArguments = AllowedWhenUntainted`; this does not establish an addon
clipboard permission. We do not call it. The UI uses the same native multiline
EditBox, `SetFocus()` and `HighlightText()` technique as the existing Diagnostics
exporter. Each displayed piece is at most 12,000 body bytes plus its identity
header, below the existing exporter's default piece size. Ctrl+C is the player's
action. Native keyboard/focus behavior still requires owner acceptance.

First-time load follows the existing launcher's combat restriction: the command
defers opening until combat ends. Once loaded, the tool captures its own frames
and snapshots in combat without moving the protected map. It does not start a
new performance session in combat. Recording stops cleanly in combat; the
existing performance engine may defer its own aggregation until combat ends.
This is unit-tested behavior, not a native taint certificate.

## Report schema 1

`kind = twichui-map-diagnostics`, `schema = 1`. Quick text is intended to stay
under 12 KiB; detailed JSON is bounded to 96 KiB. Deterministic serialization and
UTF-8-safe chunking reuse `TwichUI_Diagnostics/Json.lua`. Chunks carry the report
identity, part count, byte count and Adler-32 checksums. Strip each first header
line and concatenate the remaining bodies in order to recover JSON exactly;
the existing `Json.Join` validates this operation in tests.
Detailed JSON uses 17 significant digits for reproducible geometry; compact
summaries retain six. This does not increase the 96 KiB report limit.

| Field | Meaning |
|---|---|
| `id`, `environment` | Session report ID; addon/client versions and available build identity. Missing build hash says unavailable; no hash is guessed |
| `units`, `provenance` | World = uiMap 947 normalized east/south; zoom 1 fits world; UI viewport units; rotation radians; relative seconds and instrumented milliseconds |
| `redaction` | Explicit coordinate disclosure and excluded information |
| `description`, `stopReason`, `durationSeconds` | Player's untrusted description and actual bounded capture lifecycle |
| `current.view` | Native/host map, renderer readiness, current/pending zoom, limits, viewport, UI scale, animation/combat/deferred state; optional center/anchor/host position |
| `current.artwork` | Production layer order, alpha/visibility, city layers and mask availability |
| `current.terrain`, `current.interiors` | Pool/active/pending counts, sampled file IDs, failures, budget, alpha, crops/rotation and optional world rectangles |
| `current.cave`, `current.dungeon`, `current.markers` | Cave/floor context and marker counters/coordinate source; no marker labels or player locations |
| `events`, `eventTotals` | Ordered significant events, sequence and relative time; coalesced repeated states counted separately |
| `snapshots` | At most 24 retained production snapshots; view samples throttled to at most two per second, retained at most once/second |
| `findings` | Severity, `observed` versus `heuristic`, evidence and repeat count |
| `incidents` | Up to eight anomaly contexts, each with a snapshot and six events before/after. These survive ordinary event-ring eviction |
| `performance` | Existing R.Perf map scope measurements only. Support snapshot/export overhead has separate scopes and is excluded from map-cost findings |
| `limits`, `truncation`, `limitations` | Ring capacities, omitted samples, byte-limit trimming, absence of native images/asset proof and other evidence gaps |

Zero and false are valid values. Missing APIs use `{available:false,reason:...}`
or the explicit string `unavailable`, never an invented zero. `pendingZoom:false`
means no pending animation. Withheld coordinates carry a reason. Texture arrays
are bounded independently (32 terrain, 48 interior, 32 pending/failure entries),
with omission counters. A detailed report is not a full renderer memory dump.

An unchanged captured record serializes identically. It is not expected that
two different captures have the same ID or timings. The committed
[synthetic example](examples/map-diagnostics.json) demonstrates the schema;
it is not a report from a native client.

## Findings and interpretation for AI assistants

Start with schema/version/provenance, then `current.view`, `findings` and
`incidents`. Correlate event sequence numbers and relative timestamps with the
following code owners:

- `map/View.lua`: wheel accumulation, anchor invariants, host switching,
  zero-size/resize and combat guards. `boundary-clamp` is normal information;
  `cursor-anchor-displaced` is measured outside that legitimate boundary case.
- `map/Art.lua`: world/continent/zone/city layer selection and masks.
- `map/Detail.lua`: terrain tile availability, budget/LOD and placement.
- `map/Pictures.lua`: interior crops/rotation, texture loading and pool reuse.
- `map/Caves.lua`: cave selection, floors, surface fade and extended zoom.
- `TwichUI_Diagnostics/MapCapture.lua`: bounded recorder, findings and exports.

`inward-zoom-reversed`, `cursor-anchor-displaced`, texture failures and recorded
handler errors are observed technical failures. A context-oscillation finding is
heuristic: alternating intentional navigation can produce the same sequence.
Absent close detail may be intentional ocean, disabled detail or missing art;
do not call it a rendering failure without corroboration. Expensive R.Perf
scope time is synchronous CPU evidence, not GPU time or whole-frame blame.

No anomaly detected means exactly that. Do not invent a cause, infer successful
texture pixels from a file ID, or claim that masks/terrain align in game from
numeric geometry. Ask for a native screenshot only when artwork appearance
cannot be resolved from captured data and the offline visual lab.

## Cost, lifecycle and verification

Before the diagnostics addon loads there are no recorder frames, timers or
snapshots. Production taps are guarded by nil `R.MapTrace` and allocate nothing
while off. After loading, one view listener immediately returns while stopped.
Explicit recording installs one bounded deadline timer and may start the
existing Map performance preset; it stops only the performance session it owns.
It never replaces another ongoing capture or starts a second permanent profiler.
The UI's once-per-second status updater exists only while visible and recording.

`map.support.snapshot` and `map.support.export` are separately labelled
diagnostics overhead. The existing map render scopes/gauges remain authoritative.
Tests reuse production map Lua in the native-style MapCanvas fixture and cover
schema/JSON validity, deterministic output, privacy, unavailable APIs, bounded
histories, incident context, chunk reconstruction, start/stop/timeout, map
close/reopen, combat, injected anchor/load anomalies and UI reselection.
Actual Ctrl+C and native secure behavior remain owner-directed checks.

Optional native-style widget scenario:

```sh
source /workspace/twichui-env/activate.sh
bash tools/simlab/run.sh mapdiag
```

This stages the existing diagnostics addon in the isolated simulator and checks
17 capture/record/mark/prepare/chunk/reopen and report geometry checks, then writes a structural
PNG. Image inspection caught and corrected the report field's anchoring,
height, alignment and initial cursor position. The simulator substitutes fonts
and has no client artwork; it does not exercise a physical keyboard or clipboard.
For partial offline reconstruction from a detailed capture, see
[Map Visual Test Lab](map-visual-lab.md#import-an-in-game-diagnostic).
