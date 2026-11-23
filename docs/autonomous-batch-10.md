# Autonomous Batch 10 — Execute Range and conveniences

Baseline: `main` at `1a3d9eb`, after UX01 PR #132 merged. One consolidated draft,
no merge, deployment or release. No F27, W13, W25, Market/Opportunities/Ledger or
Reminders glow changes.

## Player changes and task status

| Task | Status | Player-visible result | Principal commit |
| --- | --- | --- | --- |
| F02 Execute Range | Implemented | Opt-in 1–100% personal threshold, independent EUI target/enemy-nameplate locations, marker/active/both styles | `a4d5a8c` |
| F16 Healer Watch communication | Implemented | Hover opens four self-status choices without capturing normal clicks; deliberate selection attempts one guarded group message | `2c19ec0`, lifecycle correction `101f5c5` |
| P02 Party Ping replay | Verified Existing | Existing arrival/replay sound and animation/navigation retained; no rewrite | `3e9adc9` (evidence only) |
| F15 Automatic Flight | Implemented safety corrections to verified existing feature | Account consent cannot travel with a profile; disabled/replaced openings cannot attempt a delayed flight | `d924cf4` |

F02's required target-frame and nameplate paths are verified against actual
EllesmereUI 9.9.1 source, not guessed Blizzard names. Secret/unreadable health
hides active edges; markers do not require health. Protected first attachment or
layout changes defer until combat ends. Unsupported providers receive no overlay.
See [source evidence and implementation limits](design/execute-range.md).

F16 uses Forever's independently configurable mouse-motion/click flags, set
outside combat. The live panel remains click-disabled; preview/move/chooser
states hide the hover surface. The self declarations do not infer another
healer's condition. Instance group takes precedence, then raid/home party. Solo,
combat, messaging lockdown, invalid/secret/missing APIs and stale context refuse
sending. Repeated selections are limited to one attempt per three seconds;
there is no whisper, queue, retry or delivery-success claim. See
[communication evidence](healer-watch-communication-discovery.md).

F15 retains the existing explicit confirmation, selected/offered journey point,
origin-distance, combat, taxi, refusal and retry guards. Two failing regressions
proved the profile-consent and pending-opening gaps before correction. The new
profile exclusion ignores stale consent in older profile records without a
migration or granting permission. A fresh flight-map opening is needed after
invalidation. See [flight verification](navigation.md#batch-10-automatic-flight-verification).
P02's existing coverage and native-only checks are [recorded separately](map-pings.md#batch-10--p02-verified-existing).

## Combined-branch verification

The existing simulator installation is absent. Per the batch instruction, it was
not repeatedly launched or repaired. The affected integration plan was previewed;
the six direct development plans have the **same union of offline modules and
syntax files** as that plan. Existing runner commands on the combined branch:

```
./tests/run.sh development navigation
./tests/run.sh development execute-range
./tests/run.sh development healer-watch
./tests/run.sh development settings
./tests/run.sh development core
./tests/run.sh development shared-ui
```

**97 unique offline modules passed** (37 Navigation, 3 Execute Range, 3 Healer
Watch, 33 Settings, 15 Core, 9 Shared UI; three modules overlap these selections).
Selected syntax passed; source fingerprints stayed unchanged within each run.
After integration exposed stale Settings registration/count/order expectations,
only the affected Settings group was rerun to PASS. After the deferred-combat
hover lifecycle regression was added/fixed, the Healer Watch group was rerun to
PASS. Earlier failures and their logs/reports remain local; they were not erased
or reclassified as successful runs.

The options-contract fixture changes only for Execute Range's five new settings,
page/rows/write/reset values and the intended Healer Watch tooltip. It now checks
753 settings / 1187 descriptor rows. Existing options retain IDs/defaults/storage.
No native or simulator acceptance, pixel/taint certificate or full/release gate is
claimed. Offline fixtures do not execute proprietary EUI source. No real chat,
network ping or flight action was sent during verification.

## Native player verification — unchecked

Execute Range:

- [ ] Configure 1%, 20%, 25%, 35% and 100%; reload and check the retained choice.
- [ ] Enable target only, enemy nameplates only, then both simultaneously.
- [ ] Cross the threshold in both directions with readable health; verify
  exact-threshold inclusion. With restricted health, active stays hidden.
- [ ] Resize/scale compact and taller EUI targets, vary nameplate widths/scales,
  and exercise supported horizontal/vertical/reverse fill directions.
- [ ] Switch targets; spawn/hide/remove/recycle plates. No old occupant's marker
  or edge may remain. Check EUI configuration changes and combat deferral.
- [ ] Disable and switch profiles; no queued overlay may reappear.
- [ ] Verify both supported EUI providers against the pinned source and safe
  hiding with unsupported/missing providers. Check text/absorbs/decorations,
  ordinary clicks/casts, blocked-action warnings and taint in the real client.

Healer Watch:

- [ ] Hover without clicking: choices appear, no message sends, and normal clicks
  still pass through the panel. Check pointer transition to the menu.
- [ ] Click each self-status in a controlled group: at most one intended message
  attempt; verify actual client permission and receipt without a synthetic success
  acknowledgement. No statement describes the watched healer automatically.
- [ ] Check party, small raid, instance party/raid (including simultaneous home
  group), solo, combat, messaging lockdown and unavailable API behavior.
- [ ] Disable, change group/profile and enter preview/move/choose-healer states
  with the menu open. Stale choices must send nothing; monitoring/alerts remain.
- [ ] First build in combat, disable before combat ends, then re-enable outside
  combat: hover setup recovers. Check scale, screen edge, Escape and click-away.

P02 native-only gaps: with two real group members, confirm actual receipt of the
ping and audible chosen sound/fallback; select a different-map entry and check
native map navigation produces its visual replay. Check actual ring/still-marker
appearance. Offline tests already cover network-send counts, rates, mute,
reduced motion and stale cancellation; those paths were not rewritten.

F15 native-only gaps: on a controlled account/client without prior consent, verify
the existing Settings confirmation/cancel dialog. At the intended flight master,
check that the native flight window highlights the actual selected destination
and whether this Forever build accepts the existing TakeTaxiNode call. If refused,
verify the native refusal and TwichUI's session-blocked status. Offline tests prove
the selection/consent/origin/combat/retry/cancellation guards; no speculative new
protected action was introduced.
